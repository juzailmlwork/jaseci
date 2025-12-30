# JAC Scale introduction

## Overview

`jac scale` is a comprehensive deployment and scaling solution for JAC applications that provides following capabilities:

### 1. Multi-Layer Memory Architecture

- **Caching Layer**: Redis for high-speed data access and session management
- **Persistence Storage**: MongoDB for reliable, long-term data storage
- **Optimized Performance**: Intelligent caching strategy to minimize database load and maximize response times

### 2. FastAPI Integration with Swagger Documentation

- Automatically converts JAC walkers and functions into RESTful FastAPI endpoints
- Built-in Swagger/OpenAPI documentation for easy API exploration and testing
- Interactive API interface accessible at `/docs` endpoint

### 3. Kubernetes Deployment & Auto-Scaling

- **Easy Deployment**: One-command deployment to Kubernetes clusters
- **Auto-Scaling**: Scale your application based on demand
- **Database Auto-Provisioning**: Automatically spawns and configures Redis and MongoDB instances
- **Production-Ready**: Built-in health checks, persistent storage, and service discovery

### 4. SSO support for login/register

### 5. Support for public private endpoints with JWT authentication

### 6. Support for websocket

## Supported jac commands
 - `jac serve`: For deploying jac application with fastapi backend
 - `jac scale`: For deploying jac application in k8s

Whether you're developing locally with `jac serve` or deploying to k8s with `jac scale`, you get the same powerful features with the flexibility to choose your deployment strategy.

## Prerequisites

- kubenetes(K8s) installed
  - [Microk8s](https://canonical.com/microk8s) (for Windows/Linux)
  - [Docker Desktop with Kubernetes](https://www.docker.com/resources/kubernetes-and-docker/) (alternative for Windows - easier setup)

**Note:** Kubernetes is only needed if you are planning to use the `jac scale` command. If you only want to use `jac serve`, Kubernetes is not required.


## Troubleshooting

### Common Issues

**Kubernetes cluster not accessible:**

- Ensure Kubernetes is running: `kubectl cluster-info`
- Check your kubeconfig: `kubectl config view`

**DockerHub authentication fails:**

- Verify your `DOCKER_USERNAME` and `DOCKER_PASSWORD` are correct
- Ensure you're using an access token (not password) if 2FA is enabled

**Namespace doesn't exist:**

- The plugin creates namespaces automatically
- If using a custom namespace, ensure proper permissions

**Database connection issues:**

- Verify StatefulSets are running: `kubectl get statefulsets -n <namespace>`
- Check pod logs: `kubectl logs <pod-name> -n <namespace>`
- Ensure persistent volumes are bound: `kubectl get pvc -n <namespace>`

**Application not accessible:**

- Check service exposure: `kubectl get svc -n <namespace>`
- Verify NodePort is not blocked by firewall
- For Minikube, use: `minikube service <service-name> -n <namespace>`

**Build failures:**

- Ensure Dockerfile exists in your application directory
- Check Docker daemon is running
- Verify sufficient disk space for image building

### Getting Help

If you encounter issues:

1. Check pod status: `kubectl get pods -n <namespace>`
2. View pod logs: `kubectl logs <pod-name> -n <namespace>`
3. Describe resources: `kubectl describe <resource-type> <resource-name> -n <namespace>`


## Next Steps

After successfully running the demo:

- **For JAC Serve**: Access your application at http://localhost:8000 and explore the Swagger documentation at http://localhost:8000/docs
- **For JAC Scale**: Access your application at http://localhost:30001 and explore the Swagger documentation at http://localhost:30001/docs
- Modify the JAC application and redeploy
- Experiment with different configuration options
- Try deploying to a production Kubernetes cluster
