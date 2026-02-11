"""Prometheus and Grafana monitoring stack deployer for Kubernetes."""
import from typing { Any }
import from jac_scale.targets.kubernetes.kubernetes_config { KubernetesConfig }
import from jac_scale.abstractions.logger { Logger }
import from jac_scale.targets.kubernetes.utils.kubernetes_utils {
    delete_if_exists,
    delete_k8s_secret
}
import from kubernetes.client.exceptions { ApiException }

"""Deploys and destroys a Prometheus + Grafana monitoring stack scoped to an app namespace.

Prometheus is always exposed as ClusterIP (internal – scraped by Grafana).
Grafana is exposed as:
  - NodePort  (non-AWS): accessible via localhost:<grafana_node_port>
  - LoadBalancer (AWS):  shares the same NLB as the app service via the
    'aws-load-balancer-name' annotation so both are reachable at
    <nlb-url>:80 (app) and <nlb-url>:3000 (Grafana).

Admin credentials for Grafana use the 'prometheus_admin_password' config value.
"""
class MonitoringDeployer {
    has k8s_config: KubernetesConfig,
        logger: (Logger | None) = None;

    def init(
        self: MonitoringDeployer,
        k8s_config: KubernetesConfig,
        logger: (Logger | None) = None
    ) -> None {
        self.k8s_config = k8s_config;
        self.logger = logger;
    }

    """Return the shared NLB name derived from the app name (max 32 chars)."""
    def _nlb_name(self: MonitoringDeployer, app_name: str) -> str {
        base = f"{app_name}-nlb";
        return base[:32];
    }

    """Deploy Prometheus – ConfigMap with scrape config + Deployment + ClusterIP Service."""
    def _deploy_prometheus(
        self: MonitoringDeployer,
        app_name: str,
        namespace: str,
        apps_v1: Any,
        core_v1: Any
    ) -> None {
        prometheus_name = f"{app_name}-prometheus";
        container_port = self.k8s_config.container_port;

        scrape_config = (
            "global:\n"
            "  scrape_interval: 15s\n"
            "  evaluation_interval: 15s\n"
            "scrape_configs:\n"
            f"  - job_name: '{app_name}'\n"
            "    static_configs:\n"
            f"      - targets: ['{app_name}-service:{container_port}']\n"
            "    metrics_path: '/metrics'\n"
        );

        prometheus_configmap = {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {
                'name': f"{prometheus_name}-config",
                'namespace': namespace,
                'labels': {'app': prometheus_name}
            },
            'data': {'prometheus.yml': scrape_config}
        };
        try {
            core_v1.read_namespaced_config_map(
                name=f"{prometheus_name}-config", namespace=namespace
            );
            core_v1.replace_namespaced_config_map(
                name=f"{prometheus_name}-config",
                namespace=namespace,
                body=prometheus_configmap
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_config_map(
                    namespace=namespace, body=prometheus_configmap
                );
            } else {
                raise ;
            }
        }

        prometheus_deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': prometheus_name,
                'namespace': namespace,
                'labels': {'app': prometheus_name}
            },
            'spec': {
                'replicas': 1,
                'selector': {'matchLabels': {'app': prometheus_name}},
                'template': {
                    'metadata': {'labels': {'app': prometheus_name}},
                    'spec': {
                        'containers': [
                            {
                                'name': 'prometheus',
                                'image': 'prom/prometheus:latest',
                                'args': [
                                    '--config.file=/etc/prometheus/prometheus.yml',
                                    '--storage.tsdb.path=/prometheus',
                                    '--web.console.libraries=/usr/share/prometheus/console_libraries',
                                    '--web.console.templates=/usr/share/prometheus/consoles'
                                ],
                                'ports': [{'containerPort': 9090}],
                                'volumeMounts': [
                                    {
                                        'name': 'prometheus-config-vol',
                                        'mountPath': '/etc/prometheus'
                                    }
                                ]
                            }
                        ],
                        'volumes': [
                            {
                                'name': 'prometheus-config-vol',
                                'configMap': {'name': f"{prometheus_name}-config"}
                            }
                        ]
                    }
                }
            }
        };
        try {
            apps_v1.read_namespaced_deployment(
                name=prometheus_name, namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                apps_v1.create_namespaced_deployment(
                    namespace=namespace, body=prometheus_deployment
                );
            } else {
                raise ;
            }
        }

        # Prometheus is ClusterIP – Grafana scrapes it internally at prometheus-service:9090
        prometheus_service = {
            'apiVersion': 'v1',
            'kind': 'Service',
            'metadata': {
                'name': f"{prometheus_name}-service",
                'namespace': namespace,
                'labels': {'app': prometheus_name}
            },
            'spec': {
                'type': 'ClusterIP',
                'selector': {'app': prometheus_name},
                'ports': [{'protocol': 'TCP', 'port': 9090, 'targetPort': 9090}]
            }
        };
        try {
            core_v1.read_namespaced_service(
                name=f"{prometheus_name}-service", namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_service(
                    namespace=namespace, body=prometheus_service
                );
            } else {
                raise ;
            }
        }

        if self.logger {
            self.logger.info(f"Prometheus deployed for '{app_name}'");
        }
    }

    """Deploy Grafana – admin Secret, datasource ConfigMap, Deployment and Service.

    On AWS the service shares the existing app NLB via aws-load-balancer-name annotation,
    so Grafana is reachable at <nlb-url>:3000.
    On non-AWS a NodePort is used.
    """
    def _deploy_grafana(
        self: MonitoringDeployer,
        app_name: str,
        namespace: str,
        apps_v1: Any,
        core_v1: Any,
        is_aws: bool
    ) -> None {
        grafana_name = f"{app_name}-grafana";
        prometheus_name = f"{app_name}-prometheus";
        grafana_secret_name = f"{grafana_name}-secret";

        # Admin credentials – password sourced from prometheus_admin_password config field
        grafana_secret = {
            'apiVersion': 'v1',
            'kind': 'Secret',
            'metadata': {
                'name': grafana_secret_name,
                'namespace': namespace,
                'labels': {'app': grafana_name}
            },
            'type': 'Opaque',
            'stringData': {
                'GF_SECURITY_ADMIN_USER': 'admin',
                'GF_SECURITY_ADMIN_PASSWORD': self.k8s_config.prometheus_admin_password
            }
        };
        try {
            core_v1.read_namespaced_secret(
                name=grafana_secret_name, namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_secret(
                    namespace=namespace, body=grafana_secret
                );
            } else {
                raise ;
            }
        }

        # Datasource ConfigMap – Prometheus is always ClusterIP at port 9090
        prometheus_url = (
            f"http://{prometheus_name}-service:9090"
            if self.k8s_config.prometheus_enabled
            else "http://prometheus:9090"
        );
        datasource_yaml = (
            "apiVersion: 1\n"
            "datasources:\n"
            "  - name: Prometheus\n"
            "    type: prometheus\n"
            f"    url: {prometheus_url}\n"
            "    isDefault: true\n"
            "    access: proxy\n"
            "    editable: true\n"
        );
        grafana_ds_configmap = {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {
                'name': f"{grafana_name}-datasources",
                'namespace': namespace,
                'labels': {'app': grafana_name}
            },
            'data': {'datasource.yaml': datasource_yaml}
        };
        try {
            core_v1.read_namespaced_config_map(
                name=f"{grafana_name}-datasources", namespace=namespace
            );
            core_v1.replace_namespaced_config_map(
                name=f"{grafana_name}-datasources",
                namespace=namespace,
                body=grafana_ds_configmap
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_config_map(
                    namespace=namespace, body=grafana_ds_configmap
                );
            } else {
                raise ;
            }
        }

        grafana_deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': grafana_name,
                'namespace': namespace,
                'labels': {'app': grafana_name}
            },
            'spec': {
                'replicas': 1,
                'selector': {'matchLabels': {'app': grafana_name}},
                'template': {
                    'metadata': {'labels': {'app': grafana_name}},
                    'spec': {
                        'containers': [
                            {
                                'name': 'grafana',
                                'image': 'grafana/grafana:latest',
                                'ports': [{'containerPort': 3000}],
                                'envFrom': [
                                    {'secretRef': {'name': grafana_secret_name}}
                                ],
                                'volumeMounts': [
                                    {
                                        'name': 'grafana-datasources-vol',
                                        'mountPath': '/etc/grafana/provisioning/datasources'
                                    }
                                ]
                            }
                        ],
                        'volumes': [
                            {
                                'name': 'grafana-datasources-vol',
                                'configMap': {'name': f"{grafana_name}-datasources"}
                            }
                        ]
                    }
                }
            }
        };
        try {
            apps_v1.read_namespaced_deployment(name=grafana_name, namespace=namespace);
        } except ApiException as e {
            if e.status == 404 {
                apps_v1.create_namespaced_deployment(
                    namespace=namespace, body=grafana_deployment
                );
            } else {
                raise ;
            }
        }

        # Service: NodePort locally, LoadBalancer sharing the app's NLB on AWS
        if is_aws {
            grafana_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': f"{grafana_name}-service",
                    'namespace': namespace,
                    'labels': {'app': grafana_name},
                    'annotations': {
                        'service.beta.kubernetes.io/aws-load-balancer-type': 'external',
                        'service.beta.kubernetes.io/aws-load-balancer-scheme': 'internet-facing',
                        'service.beta.kubernetes.io/aws-load-balancer-nlb-target-type': 'ip',
                        # Share the same NLB as the main app service
                        'service.beta.kubernetes.io/aws-load-balancer-name': self._nlb_name(
                            app_name
                        )
                    }
                },
                'spec': {
                    'type': 'LoadBalancer',
                    'selector': {'app': grafana_name},
                    'ports': [{'protocol': 'TCP', 'port': 3000, 'targetPort': 3000}]
                }
            };
        } else {
            grafana_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': f"{grafana_name}-service",
                    'namespace': namespace,
                    'labels': {'app': grafana_name}
                },
                'spec': {
                    'type': 'NodePort',
                    'selector': {'app': grafana_name},
                    'ports': [
                        {
                            'protocol': 'TCP',
                            'port': 3000,
                            'targetPort': 3000,
                            'nodePort': self.k8s_config.grafana_node_port
                        }
                    ]
                }
            };
        }

        try {
            core_v1.read_namespaced_service(
                name=f"{grafana_name}-service", namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_service(
                    namespace=namespace, body=grafana_service
                );
            } else {
                raise ;
            }
        }

        if self.logger {
            if is_aws {
                self.logger.info(
                    f"Grafana deployed for '{app_name}' – accessible at NLB '{self._nlb_name(
                        app_name
                    )}' on port 3000"
                );
            } else {
                self.logger.info(
                    f"Grafana deployed for '{app_name}' – accessible at localhost:{self.k8s_config.grafana_node_port}"
                );
            }
        }
    }

    """Deploy the full monitoring stack (Prometheus and/or Grafana) for an app namespace."""
    def deploy(
        self: MonitoringDeployer,
        app_name: str,
        namespace: str,
        apps_v1: Any,
        core_v1: Any,
        is_aws: bool
    ) -> None {
        if not self.k8s_config.monitoring_enabled {
            return;
        }

        self._deploy_prometheus(app_name, namespace, apps_v1, core_v1);
        self._deploy_grafana(app_name, namespace, apps_v1, core_v1, is_aws);
    }

    """Destroy all Prometheus and Grafana resources for an app namespace."""
    def destroy(
        self: MonitoringDeployer,
        app_name: str,
        namespace: str,
        apps_v1: Any,
        core_v1: Any
    ) -> None {
        prometheus_name = f"{app_name}-prometheus";
        grafana_name = f"{app_name}-grafana";

        # Prometheus resources
        delete_if_exists(
            apps_v1.delete_namespaced_deployment,
            prometheus_name,
            namespace,
            'Deployment'
        );
        delete_if_exists(
            core_v1.delete_namespaced_service,
            f"{prometheus_name}-service",
            namespace,
            'Service'
        );
        try {
            core_v1.delete_namespaced_config_map(
                name=f"{prometheus_name}-config", namespace=namespace
            );
        } except ApiException as e {
            if e.status != 404 {
                raise ;
            }
        }

        # Grafana resources
        delete_if_exists(
            apps_v1.delete_namespaced_deployment, grafana_name, namespace, 'Deployment'
        );
        delete_if_exists(
            core_v1.delete_namespaced_service,
            f"{grafana_name}-service",
            namespace,
            'Service'
        );
        try {
            core_v1.delete_namespaced_config_map(
                name=f"{grafana_name}-datasources", namespace=namespace
            );
        } except ApiException as e {
            if e.status != 404 {
                raise ;
            }
        }
        delete_k8s_secret(core_v1, namespace, f"{grafana_name}-secret");

        if self.logger {
            self.logger.info(f"Monitoring stack destroyed for '{app_name}'");
        }
    }
}
