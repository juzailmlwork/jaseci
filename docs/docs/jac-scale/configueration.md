## Jac scale configueration

### Environment Variables

| Parameter | Description | Default |
|-----------|-------------|---------|
| `APP_NAME` | Name of your JAC application | `jaseci` |
| `DOCKER_USERNAME` | DockerHub username for pushing the image | - |
| `DOCKER_PASSWORD` | DockerHub password or access token | - |
| `K8s_NAMESPACE` | Kubernetes namespace to deploy the application | `default` |
| `K8s_NODE_PORT` | Port in which your local kubernetes application will run on| `30001` |
| `K8s_CPU_REQUEST` | CPU request for the application container | - |
| `K8s_CPU_LIMIT` | CPU limit for the application container | - |
| `K8s_MEMORY_REQUEST` | Memory request for the application container | - |
| `K8s_MEMORY_LIMIT` | Memory limit for the application container | - |
| `K8s_READINESS_INITIAL_DELAY` | Seconds before readiness probe first checks the pod | `120` |
| `K8s_READINESS_PERIOD` | Seconds between readiness probe checks | `30` |
| `K8s_LIVENESS_INITIAL_DELAY` | Seconds before liveness probe first checks the pod | `120` |
| `K8s_LIVENESS_PERIOD` | Seconds between liveness probe checks | `30` |
| `K8s_LIVENESS_FAILURE_THRESHOLD` | Consecutive liveness probe failures before restart | `10` |
| `K8s_MONGODB` | Whether MongoDB is needed (`True`/`False`) | `True` |
| `K8s_REDIS` | Whether Redis is needed (`True`/`False`) | `True` |

### Environment Variables

| Parameter | Description | Default |
|-----------|-------------|---------|
| `MONGODB_URI` | URL of MongoDB database | - |
| `REDIS_URL` | URL of Redis database | - |

### Environment Variables

| `JWT_EXP_DELTA_DAYS` | Number of days until JWT token expires | `7` |
| `JWT_SECRET` | Secret key used for JWT token signing and verification | `'supersecretkey'` |
| `JWT_ALGORITHM` | Algorithm used for JWT token encoding/decoding | `'HS256'` |
| `SSO_HOST` | SSO host URL | `'http://localhost:8000/sso'` |
| `SSO_GOOGLE_CLIENT_ID` | Google OAuth client ID | - |
| `SSO_GOOGLE_CLIENT_SECRET` | Google OAuth client secret | - |

### Environment Variables

| `JWT_EXP_DELTA_DAYS` | Number of days until JWT token expires | `7` |
| `JWT_SECRET` | Secret key used for JWT token signing and verification | `'supersecretkey'` |
| `JWT_ALGORITHM` | Algorithm used for JWT token encoding/decoding | `'HS256'` |
| `SSO_HOST` | SSO host URL | `'http://localhost:8000/sso'` |
| `SSO_GOOGLE_CLIENT_ID` | Google OAuth client ID | - |
| `SSO_GOOGLE_CLIENT_SECRET` | Google OAuth client secret | - |

## Important Notes

### Implementation

- The entire `jac scale` plugin is implemented using **Python and Kubernetes Python client libraries**
- **No custom Kubernetes controllers** are used → easier to deploy and maintain

### Database Provisioning

- Databases are created as **StatefulSets** with persistent storage
- Databases are **only created on the first run**
- Subsequent `jac scale` calls only update application deployments
- This ensures persistent storage and avoids recreating databases unnecessarily

### Performance

- **First-time deployment** may take longer due to database provisioning and image downloading
- **Subsequent deployments** are faster since:
  - Only the application's final Docker layer is pushed and pulled
  - Only deployments are updated (databases remain unchanged)
