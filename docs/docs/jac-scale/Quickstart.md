# Quick Start: Running Todo application with frontend

Follow these steps to set up and test the Todo application with frontend

### 1. Clone the Jaseci Repository

First, clone the main Jaseci repository which contains JAC and JAC-Scale:

```bash
git clone https://github.com/jaseci-labs/jaseci.git
cd jaseci
git submodule update --init --recursive
```

### 2. Create Python Virtual Environment

```bash
python -m venv venv
```

### 3. Activate the Virtual Environment

**Linux/Mac:**

```bash
source venv/bin/activate
```

**Windows:**

```bash
venv\Scripts\activate
```

### 4. Install JAC, JAC-Scale and JAC-Client

Install the packages in editable mode from the cloned repository:

```bash
pip install -e ./jac
pip install -e ./jac-scale
pip install -e ./jac-client
```

### 5. Create Todo application using jac-client

Lets create the todo application using jac client.For that lets create a folder called todo and run jac create command provided by jac client

```bash
mkdir todo
cd todo
jac create app
```

Then lets copy the todo fully implemented jac code available inside jac-scale/examples/todo to our newly created /todo folder

```bash
cp ../jac-scale/examples/todo/app.jac app.jac
```

### 8. Run the Application with JAC Scale

To run your application run the following command

```bash
jac serve app.jac
```

**Access your application:**

- Frontend: http://localhost:8000/page/app
- Backend: http://localhost:8000
- Swagger Documentation: http://localhost:8000/docs

you can add new todo tasks

- from the frontend at http://localhost:8000/page/app
- from the swagger docs  at http://localhost:8000/docs using /walker/create-todo endpoint

### 9. Set Up Kubernetes (For JAC Scale)

To use `jac scale`, you need Kubernetes installed on your machine.

**Option A: MicroK8 (Windows/Linux/Mac)**

- [Official MicroK8 installation guide](https://microk8s.io/)
- [ubunutu installation guide](https://www.digitalocean.com/community/tutorials/how-to-setup-a-microk8s-kubernetes-cluster-on-ubuntu-22-04)

**Option B: Docker Desktop with Kubernetes (Windows - Recommended)**

- Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- Enable Kubernetes in Docker Desktop settings (easier setup)

### 10. Deploy with JAC Scale

Once Kubernetes is running, you have two deployment methods:

#### Method A: Deploy Without Building (Faster)

Deploy your application to Kubernetes without building a Docker image:

```bash
jac scale app.jac
```

**Access your application:**

- Frontend: http://localhost:30001/page/app
- Backend: http://localhost:30001
- Swagger Documentation: http://localhost:30001/docs

**Use this when:**

- You want faster deployments without rebuilding
- You're testing configuration changes
- You're in development mode

#### Method B: Build, Push, and Deploy (Production)

To Build your application as a Docker image and deploy it kubernetes you can run

```bash
jac scale app.jac -b
```
**Requirements for Build Mode:**

- A `Dockerfile` in your application directory
- Dockerhub account
- Environment variables set:
  - `DOCKER_USERNAME` - Your DockerHub username
  - `DOCKER_PASSWORD` - Your DockerHub password/access token

**Access your application:**

- Frontend: http://localhost:30001/page/app
- Backend: http://localhost:30001
- Swagger Documentation: http://localhost:30001/docs

**Use this when:**

- Deploying to production
- You want to version and host your Docker image
- Sharing your application with others
- Creating reproducible deployments

### 11. Clean Up Kubernetes Resources

When you're done testing, remove all created Kubernetes resources:

```bash
jac destroy app.jac
```

**What this does:**

- Deletes all Kubernetes deployments, services, and StatefulSets
- Removes persistent volumes and claims
- Cleans up the namespace (if custom namespace was used)