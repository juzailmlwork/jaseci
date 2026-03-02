"""Kubernetes Redis provider implementation."""
import from typing { Any }
import from jac_scale.abstractions.database_provider { DatabaseProvider }
import from jac_scale.abstractions.deployment_target { DeploymentTarget }

"""Redis provider for Kubernetes deployments."""
class KubernetesRedisProvider(DatabaseProvider) {
    has target: (DeploymentTarget | None) = None,
        config: dict[str, Any] = {},
        app_name: str = '',
        connection_string: str = '';

    def init(
        self: KubernetesRedisProvider,
        target: (DeploymentTarget | None) = None,
        config: dict[str, Any] = {}
    ) -> None {
        self.target = target;
        self.config = config;
        self.app_name = config.get('app_name', 'jaseci');
    }

    def deploy(
        self: KubernetesRedisProvider, config: dict[str, Any] = {}
    ) -> dict[str, Any] {
        redis_name = f"{self.app_name}-redis";
        redis_port = 6379;
        redis_service_name = f"{redis_name}-service";

        redis_deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {'name': redis_name, 'labels': {'managed': 'jac-scale'}},
            'spec': {
                'replicas': 1,
                'selector': {'matchLabels': {'app': redis_name}},
                'template': {
                    'metadata': {'labels': {'app': redis_name}},
                    'spec': {
                        'containers': [
                            {
                                'name': 'redis',
                                'image': 'redis:7.2',
                                'ports': [{'containerPort': redis_port}],
                                'args': ['--save', '', '--appendonly', 'no'],
                                'resources': {
                                    'requests': {'cpu': '100m', 'memory': '128Mi'},
                                    'limits': {'cpu': '500m', 'memory': '256Mi'}
                                }
                            }
                        ]
                    }
                }
            }
        };

        redis_service = {
            'apiVersion': 'v1',
            'kind': 'Service',
            'metadata': {
                'name': redis_service_name,
                'labels': {'managed': 'jac-scale'}
            },
            'spec': {
                'selector': {'app': redis_name},
                'ports': [
                    {'protocol': 'TCP', 'port': redis_port, 'targetPort': redis_port}
                ]
            }
        };

        self.connection_string = f"redis://{redis_service_name}:{redis_port}/0";

        return {
            'deployment': redis_deployment,
            'service': redis_service,
            'connection_string': self.connection_string,
            'service_name': redis_service_name
        };
    }

    def get_connection_string(self: KubernetesRedisProvider) -> str {
        if not self.connection_string {
            # Generate default connection string
            service_name = f"{self.app_name}-redis-service";
            self.connection_string = f"redis://{service_name}:6379/0";
        }
        return self.connection_string;
    }

    def is_available(self: KubernetesRedisProvider) -> bool {
        # TODO: Implement actual check
        return True;
    }

    def cleanup(self: KubernetesRedisProvider) -> None {
    # Cleanup is handled by the deployment target
    }

    override def get_init_container(
        self: KubernetesRedisProvider, app_name: str, wait_image: str
    ) -> (dict[(str, Any)] | None) {
        return {
            'name': 'wait-for-redis',
            'image': wait_image,
            'command': [
                'sh',
                '-c',
                f"until nc -z {app_name}-redis-service 6379; do echo waiting for redis; sleep 3; done"
            ]
        };
    }

    """Return RedisInsight dashboard resource specs.

    Returns deployment and service specs for the caller to apply via the K8s API.
    Follows the same pattern as deploy(): pure spec construction, no API calls.
    """
    def deploy_dashboard(
        self: KubernetesRedisProvider,
        cluster_env: str,
        node_port: int
    ) -> dict[str, Any] {
        redis_service_name = f"{self.app_name}-redis-service";
        insight_name = f"{self.app_name}-redis-insight";

        # RedisInsight v3 supports RI_REDIS_HOST / RI_REDIS_PORT env vars to
        # pre-seed a database connection on first start (no manual setup needed).
        insight_deployment = {
            'apiVersion': 'apps/v1',
            'kind': 'Deployment',
            'metadata': {
                'name': insight_name,
                'labels': {'app': insight_name, 'managed': 'jac-scale'}
            },
            'spec': {
                'replicas': 1,
                'selector': {'matchLabels': {'app': insight_name}},
                'template': {
                    'metadata': {'labels': {'app': insight_name}},
                    'spec': {
                        'containers': [
                            {
                                'name': 'redisinsight',
                                'image': 'redis/redisinsight:3.2.0',
                                'ports': [{'containerPort': 5540}],
                                'env': [
                                    {
                                        'name': 'RI_REDIS_HOST',
                                        'value': redis_service_name
                                    },
                                    {'name': 'RI_REDIS_PORT', 'value': '6379'},
                                    {'name': 'RI_REDIS_ALIAS', 'value': 'Jaseci Redis'}
                                ],
                                'resources': {
                                    'requests': {'cpu': '100m', 'memory': '128Mi'},
                                    'limits': {'cpu': '500m', 'memory': '512Mi'}
                                }
                            }
                        ]
                    }
                }
            }
        };

        if cluster_env == 'aws' {
            insight_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': f"{insight_name}-service",
                    'labels': {'app': insight_name, 'managed': 'jac-scale'},
                    'annotations': {
                        'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb'
                    }
                },
                'spec': {
                    'type': 'LoadBalancer',
                    'selector': {'app': insight_name},
                    'ports': [{'protocol': 'TCP', 'port': 80, 'targetPort': 5540}]
                }
            };
        } else {
            insight_service = {
                'apiVersion': 'v1',
                'kind': 'Service',
                'metadata': {
                    'name': f"{insight_name}-service",
                    'labels': {'app': insight_name, 'managed': 'jac-scale'}
                },
                'spec': {
                    'type': 'NodePort',
                    'selector': {'app': insight_name},
                    'ports': [
                        {
                            'protocol': 'TCP',
                            'port': 5540,
                            'targetPort': 5540,
                            'nodePort': node_port
                        }
                    ]
                }
            };
        }

        return {
            'deployment': insight_deployment,
            'service': insight_service,
            'deployment_name': insight_name,
            'service_name': f"{insight_name}-service"
        };
    }
}
