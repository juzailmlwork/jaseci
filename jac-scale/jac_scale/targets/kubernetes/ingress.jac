"""NGINX Ingress controller and Ingress resource deployer."""
import from typing { Any }
import from kubernetes { client }
import from jac_scale.targets.kubernetes.kubernetes_config { KubernetesConfig }
import from jac_scale.abstractions.logger { Logger }
import from jac_scale.targets.kubernetes.utils.kubernetes_utils { delete_if_exists }
import from kubernetes.client.exceptions { ApiException }

"""Deploys and manages an app-scoped NGINX Ingress controller plus Ingress routing rules.

One controller per app, identified by ingress class '{app_name}-nginx'.

Routes (local: http://<node-ip>:30080, AWS: NLB port 80):
  /               -> {app_name}-service
  /grafana        -> {app_name}-grafana-service   (Grafana handles subpath via GF_SERVER env)
  /db-dashboard  -> {app_name}-mongo-express-service  (MongoExpress handles subpath via ME_CONFIG_SITE_BASEURL)
  /cache-dashboard  -> {app_name}-redis-insight-service  (separate Ingress with rewrite-target)
"""
obj IngressDeployer {
    has k8s_config: KubernetesConfig,
        logger: (Logger | None) = None;

    """Deploy the NGINX Ingress controller: ServiceAccount, ClusterRole, ClusterRoleBinding,
    ConfigMap, IngressClass, Deployment, and Service (NodePort locally / NLB on AWS)."""
    def _deploy_nginx_controller(
        app_name: str,
        namespace: str,
        cluster_env: str,
        apps_v1: Any,
        core_v1: Any,
        rbac_v1: Any,
        networking_v1: Any
    ) -> None {
        controller_name = f"{app_name}-ingress-nginx";
        configmap_name = f"{app_name}-nginx-configuration";
        ingress_class_name = f"{app_name}-nginx";
        service_name = f"{controller_name}-service";

        # --- ServiceAccount ---
        sa = {
            'apiVersion': 'v1',
            'kind': 'ServiceAccount',
            'metadata': {
                'name': controller_name,
                'namespace': namespace,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            }
        };
        try {
            core_v1.read_namespaced_service_account(
                name=controller_name, namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_service_account(
                    namespace=namespace, body=sa
                );
            } else {
                raise;
            }
        }

        # --- ClusterRole ---
        cluster_role = {
            'apiVersion': 'rbac.authorization.k8s.io/v1',
            'kind': 'ClusterRole',
            'metadata': {
                'name': controller_name,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            },
            'rules': [
                # Core reads (cluster-wide)
                {
                    'apiGroups': [''],
                    'resources': ['configmaps', 'endpoints', 'nodes', 'pods', 'secrets', 'namespaces'],
                    'verbs': ['get', 'list', 'watch']
                },
                # ConfigMap writes (leader-election lock)
                {
                    'apiGroups': [''],
                    'resources': ['configmaps'],
                    'verbs': ['create', 'update']
                },
                {
                    'apiGroups': [''],
                    'resources': ['services'],
                    'verbs': ['get', 'list', 'watch']
                },
                {
                    'apiGroups': [''],
                    'resources': ['events'],
                    'verbs': ['create', 'patch']
                },
                # Leader-election leases
                {
                    'apiGroups': ['coordination.k8s.io'],
                    'resources': ['leases'],
                    'verbs': ['get', 'list', 'watch', 'create', 'update']
                },
                {
                    'apiGroups': ['networking.k8s.io'],
                    'resources': ['ingresses'],
                    'verbs': ['get', 'list', 'watch']
                },
                {
                    'apiGroups': ['networking.k8s.io'],
                    'resources': ['ingresses/status'],
                    'verbs': ['update']
                },
                {
                    'apiGroups': ['networking.k8s.io'],
                    'resources': ['ingressclasses'],
                    'verbs': ['get', 'list', 'watch']
                },
                {
                    'apiGroups': ['discovery.k8s.io'],
                    'resources': ['endpointslices'],
                    'verbs': ['get', 'list', 'watch']
                }
            ]
        };
        try {
            rbac_v1.read_cluster_role(name=controller_name);
            rbac_v1.replace_cluster_role(name=controller_name, body=cluster_role);
        } except ApiException as e {
            if e.status == 404 {
                rbac_v1.create_cluster_role(body=cluster_role);
            } else {
                raise;
            }
        }

        # --- ClusterRoleBinding ---
        crb = {
            'apiVersion': 'rbac.authorization.k8s.io/v1',
            'kind': 'ClusterRoleBinding',
            'metadata': {
                'name': controller_name,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            },
            'roleRef': {
                'apiGroup': 'rbac.authorization.k8s.io',
                'kind': 'ClusterRole',
                'name': controller_name
            },
            'subjects': [
                {
                    'kind': 'ServiceAccount',
                    'name': controller_name,
                    'namespace': namespace
                }
            ]
        };
        try {
            rbac_v1.read_cluster_role_binding(name=controller_name);
            rbac_v1.replace_cluster_role_binding(name=controller_name, body=crb);
        } except ApiException as e {
            if e.status == 404 {
                rbac_v1.create_cluster_role_binding(body=crb);
            } else {
                raise;
            }
        }

        # --- ConfigMap (empty — controller uses defaults) ---
        cm = {
            'apiVersion': 'v1',
            'kind': 'ConfigMap',
            'metadata': {
                'name': configmap_name,
                'namespace': namespace,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            },
            'data': {}
        };
        try {
            core_v1.read_namespaced_config_map(
                name=configmap_name, namespace=namespace
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_config_map(
                    namespace=namespace, body=cm
                );
            } else {
                raise;
            }
        }

        # --- IngressClass ---
        ingress_class = {
            'apiVersion': 'networking.k8s.io/v1',
            'kind': 'IngressClass',
            'metadata': {
                'name': ingress_class_name,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            },
            'spec': {'controller': 'k8s.io/ingress-nginx'}
        };
        try {
            networking_v1.read_ingress_class(name=ingress_class_name);
        } except ApiException as e {
            if e.status == 404 {
                networking_v1.create_ingress_class(body=ingress_class);
            } else {
                raise;
            }
        }

        # --- Controller Deployment ---
        controller_deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': controller_name,
                'namespace': namespace,
                'labels': {'app': controller_name, 'managed': 'jac-scale'}
            },
            'spec': {
                'replicas': 1,
                'selector': {'matchLabels': {'app': controller_name}},
                'template': {
                    'metadata': {'labels': {'app': controller_name}},
                    'spec': {
                        'serviceAccountName': controller_name,
                        'containers': [
                            {
                                'name': 'controller',
                                'image': 'registry.k8s.io/ingress-nginx/controller:v1.12.0',
                                'args': [
                                    '/nginx-ingress-controller',
                                    f"--ingress-class={ingress_class_name}",
                                    '--controller-class=k8s.io/ingress-nginx',
                                    f"--watch-namespace={namespace}",
                                    f"--configmap={namespace}/{configmap_name}",
                                    '--election-id=ingress-controller-leader',
                                    '--validating-webhook='
                                ],
                                'env': [
                                    {
                                        'name': 'POD_NAME',
                                        'valueFrom': {
                                            'fieldRef': {'fieldPath': 'metadata.name'}
                                        }
                                    },
                                    {
                                        'name': 'POD_NAMESPACE',
                                        'valueFrom': {
                                            'fieldRef': {'fieldPath': 'metadata.namespace'}
                                        }
                                    }
                                ],
                                'ports': [
                                    {'name': 'http', 'containerPort': 80},
                                    {'name': 'https', 'containerPort': 443},
                                    {'name': 'webhook', 'containerPort': 8443}
                                ],
                                'resources': {
                                    'requests': {'cpu': '100m', 'memory': '90Mi'},
                                    'limits': {'cpu': '500m', 'memory': '256Mi'}
                                }
                            }
                        ]
                    }
                }
            }
        };
        try {
            apps_v1.patch_namespaced_deployment(
                name=controller_name, namespace=namespace, body=controller_deployment
            );
        } except ApiException as e {
            if e.status == 404 {
                apps_v1.create_namespaced_deployment(
                    namespace=namespace, body=controller_deployment
                );
            } else {
                raise;
            }
        }

        # --- Service: NodePort locally, NLB on AWS ---
        if cluster_env == 'aws' {
            controller_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': service_name,
                    'namespace': namespace,
                    'labels': {'app': controller_name, 'managed': 'jac-scale'},
                    'annotations': {
                        'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb',
                        'service.beta.kubernetes.io/aws-load-balancer-scheme': 'internet-facing'
                    }
                },
                'spec': {
                    'type': 'LoadBalancer',
                    'selector': {'app': controller_name},
                    'ports': [
                        {
                            'name': 'http',
                            'protocol': 'TCP',
                            'port': 80,
                            'targetPort': 80
                        },
                        {
                            'name': 'https',
                            'protocol': 'TCP',
                            'port': 443,
                            'targetPort': 443
                        }
                    ]
                }
            };
        } else {
            controller_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': service_name,
                    'namespace': namespace,
                    'labels': {'app': controller_name, 'managed': 'jac-scale'}
                },
                'spec': {
                    'type': 'NodePort',
                    'selector': {'app': controller_name},
                    'ports': [
                        {
                            'name': 'http',
                            'protocol': 'TCP',
                            'port': 80,
                            'targetPort': 80,
                            'nodePort': self.k8s_config.ingress_node_port
                        },
                        {
                            'name': 'https',
                            'protocol': 'TCP',
                            'port': 443,
                            'targetPort': 443
                        }
                    ]
                }
            };
        }
        try {
            core_v1.patch_namespaced_service(
                name=service_name, namespace=namespace, body=controller_service
            );
        } except ApiException as e {
            if e.status == 404 {
                core_v1.create_namespaced_service(
                    namespace=namespace, body=controller_service
                );
            } else {
                raise;
            }
        }

        if self.logger {
            if cluster_env == 'aws' {
                self.logger.info(
                    f"NGINX ingress controller deployed for '{app_name}' (AWS NLB)"
                );
            } else {
                self.logger.info(
                    f"NGINX ingress controller deployed for '{app_name}' at localhost:{self.k8s_config.ingress_node_port}"
                );
            }
        }
    }

    """Deploy Ingress routing rules.

    Main Ingress: routes /, /grafana (if enabled), /db-dashboard (if enabled).
    RedisInsight Ingress (separate): routes /cache-dashboard with rewrite-target so the
    prefix is stripped before hitting the service.

    ingress_host: optional hostname; empty string = wildcard (matches all hosts).
    """
    def _deploy_ingress_resource(
        app_name: str,
        namespace: str,
        ingress_host: str,
        ingress_class: str,
        service_port: int,
        grafana_enabled: bool,
        redis_dashboard: bool,
        mongo_dashboard: bool,
        networking_v1: Any
    ) -> None {
        ingress_name = f"{app_name}-ingress";
        redis_ingress_name = f"{app_name}-redis-insight-ingress";

        # --- Build main ingress paths ---
        paths = [
            {
                'path': '/',
                'pathType': 'Prefix',
                'backend': {
                    'service': {
                        'name': f"{app_name}-service",
                        'port': {'number': service_port}
                    }
                }
            }
        ];

        if grafana_enabled {
            paths.append(
                {
                    'path': '/grafana',
                    'pathType': 'Prefix',
                    'backend': {
                        'service': {
                            'name': f"{app_name}-grafana-service",
                            'port': {'number': 3000}
                        }
                    }
                }
            );
        }

        if mongo_dashboard {
            paths.append(
                {
                    'path': '/db-dashboard',
                    'pathType': 'Prefix',
                    'backend': {
                        'service': {
                            'name': f"{app_name}-mongo-express-service",
                            'port': {'number': 8081}
                        }
                    }
                }
            );
        }

        main_rule: dict = {'http': {'paths': paths}};
        if ingress_host {
            main_rule['host'] = ingress_host;
        }

        main_ingress = {
            'apiVersion': 'networking.k8s.io/v1',
            'kind': 'Ingress',
            'metadata': {
                'name': ingress_name,
                'namespace': namespace,
                'labels': {'app': app_name, 'managed': 'jac-scale'},
                'annotations': {
                    'nginx.ingress.kubernetes.io/proxy-body-size': '0',
                    'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
                    'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600'
                }
            },
            'spec': {
                'ingressClassName': ingress_class,
                'rules': [main_rule]
            }
        };
        try {
            networking_v1.patch_namespaced_ingress(
                name=ingress_name, namespace=namespace, body=main_ingress
            );
        } except ApiException as e {
            if e.status == 404 {
                networking_v1.create_namespaced_ingress(
                    namespace=namespace, body=main_ingress
                );
            } else {
                raise;
            }
        }

        # --- RedisInsight Ingress (with rewrite-target to strip /cache-dashboard prefix) ---
        if redis_dashboard {
            # Determine the redis-insight service port (8080 when nginx-auth sidecar is
            # enabled, i.e. username and password are both set; otherwise 5540).
            auth_enabled = bool(
                self.k8s_config.redis_insight_username
                and self.k8s_config.redis_insight_password
            );
            redis_service_port = 8080 if auth_enabled else 5540;

            # No rewrite — RIPROXYPATH=/cache-dashboard is set on the container so
            # Redis Insight expects to receive the full /cache-dashboard/... path.
            redis_rule: dict = {
                'http': {
                    'paths': [
                        {
                            'path': '/cache-dashboard',
                            'pathType': 'Prefix',
                            'backend': {
                                'service': {
                                    'name': f"{app_name}-redis-insight-service",
                                    'port': {'number': redis_service_port}
                                }
                            }
                        }
                    ]
                }
            };
            if ingress_host {
                redis_rule['host'] = ingress_host;
            }

            redis_ingress = {
                'apiVersion': 'networking.k8s.io/v1',
                'kind': 'Ingress',
                'metadata': {
                    'name': redis_ingress_name,
                    'namespace': namespace,
                    'labels': {'app': app_name, 'managed': 'jac-scale'},
                    'annotations': {
                        'nginx.ingress.kubernetes.io/proxy-body-size': '0',
                        'nginx.ingress.kubernetes.io/proxy-read-timeout': '3600',
                        'nginx.ingress.kubernetes.io/proxy-send-timeout': '3600'
                    }
                },
                'spec': {
                    'ingressClassName': ingress_class,
                    'rules': [redis_rule]
                }
            };
            try {
                networking_v1.patch_namespaced_ingress(
                    name=redis_ingress_name, namespace=namespace, body=redis_ingress
                );
            } except ApiException as e {
                if e.status == 404 {
                    networking_v1.create_namespaced_ingress(
                        namespace=namespace, body=redis_ingress
                    );
                } else {
                    raise;
                }
            }
        }

        if self.logger {
            self.logger.info(f"Ingress routing rules deployed for '{app_name}'");
        }
    }

    """Tear down all ingress resources created by this deployer."""
    def destroy(
        app_name: str,
        namespace: str,
        apps_v1: Any,
        core_v1: Any,
        rbac_v1: Any,
        networking_v1: Any
    ) -> None {
        controller_name = f"{app_name}-ingress-nginx";
        ingress_class_name = f"{app_name}-nginx";
        ingress_name = f"{app_name}-ingress";
        redis_ingress_name = f"{app_name}-redis-insight-ingress";
        service_name = f"{controller_name}-service";
        configmap_name = f"{app_name}-nginx-configuration";

        # Delete namespaced Ingress resources
        delete_if_exists(
            networking_v1.delete_namespaced_ingress, ingress_name, namespace, 'Ingress'
        );
        delete_if_exists(
            networking_v1.delete_namespaced_ingress,
            redis_ingress_name,
            namespace,
            'Ingress'
        );

        # Delete controller namespaced resources
        delete_if_exists(
            apps_v1.delete_namespaced_deployment,
            controller_name,
            namespace,
            'Deployment'
        );
        delete_if_exists(
            core_v1.delete_namespaced_service, service_name, namespace, 'Service'
        );
        delete_if_exists(
            core_v1.delete_namespaced_service_account,
            controller_name,
            namespace,
            'ServiceAccount'
        );
        delete_if_exists(
            core_v1.delete_namespaced_config_map,
            configmap_name,
            namespace,
            'ConfigMap'
        );

        # Delete cluster-scoped resources (no namespace parameter)
        try {
            rbac_v1.delete_cluster_role(name=controller_name);
        } except ApiException as e {
            if e.status != 404 {
                raise;
            }
        }
        try {
            rbac_v1.delete_cluster_role_binding(name=controller_name);
        } except ApiException as e {
            if e.status != 404 {
                raise;
            }
        }
        try {
            networking_v1.delete_ingress_class(name=ingress_class_name);
        } except ApiException as e {
            if e.status != 404 {
                raise;
            }
        }

        if self.logger {
            self.logger.info(f"Ingress resources destroyed for '{app_name}'");
        }
    }
}
