# Apache Superset Kubernetes Deployment

Production-ready Kubernetes deployment configuration for Apache Superset with MySQL connectivity support.

## Overview

This repository contains Kubernetes deployment configurations for Apache Superset with:
- Custom Docker image with MySQL drivers (PyMySQL + MySQLdb compatibility)
- PostgreSQL metadata storage for production
- SQLite option for development
- Embedded dashboard support
- Automated initialization and setup

## Quick Start

### Prerequisites

**Required Software:**
- Kubernetes cluster (Minikube, EKS, GKE, AKS, etc.)
- kubectl configured and connected to your cluster
- Helm 3.x installed
- Docker installed locally

**Production Deployment Prerequisites:**
1. **Custom Docker Image Built:**
   ```bash
   docker build -t superset-mysql:latest .
   minikube image load superset-mysql:latest  # For Minikube
   ```

2. **Helm Repository Added:**
   ```bash
   helm repo add superset https://apache.github.io/superset
   helm repo update
   ```

3. **Namespace Created:**
   ```bash
   kubectl create namespace production
   ```

4. **PostgreSQL Deployed First:**
   ```bash
   kubectl apply -f postgres-production.yaml
   kubectl wait --for=condition=ready pod -l app=postgresql -n production --timeout=120s
   ```

5. **Cluster Resources Available:**
   - Minimum 3 CPUs available
   - Minimum 4GB RAM available
   - Persistent storage class configured (for 5Gi PostgreSQL PVC)

6. **Python Packages (installed automatically via bootstrapScript):**
   - psycopg2-binary (PostgreSQL driver)
   - PyMySQL (MySQL driver)
   - MySQLdb compatibility module

### Development Deployment

```bash
# Build custom image
docker build -t superset-mysql:latest .
minikube image load superset-mysql:latest

# Add Helm repo
helm repo add superset https://apache.github.io/superset
helm repo update

# Deploy
kubectl create namespace dev
helm install superset superset/superset \
  --namespace dev \
  --values simple-superset-values.yaml

# Access
kubectl port-forward service/superset 8081:8088 -n dev
# Open http://localhost:8081 (admin/admin)
```

### Production Deployment

```bash
# Build and load custom image
docker build -t superset-mysql:latest .
minikube image load superset-mysql:latest

# Create namespace
kubectl create namespace production

# Deploy PostgreSQL
kubectl apply -f postgres-production.yaml
kubectl wait --for=condition=ready pod -l app=postgresql -n production --timeout=120s

# Deploy Superset
helm install superset superset/superset \
  --namespace production \
  --values production-superset-values.yaml

# Access
kubectl port-forward service/superset 8081:8088 -n production
# Open http://localhost:8081 (admin/admin)
```

## Configuration Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Custom Superset image with MySQL drivers |
| `production-superset-values.yaml` | Production Helm values (PostgreSQL, 2 replicas, Keycloak SSO) |
| `dev-superset-values.yaml` | Development Helm values (SQLite, 1 replica) |
| `simple-superset-values.yaml` | Minimal development configuration |
| `postgres-production.yaml` | PostgreSQL deployment for production |
| `docker-compose-keycloak.yaml` | Keycloak Docker Compose for SSO |
| `PRODUCTION-DEPLOYMENT-GUIDE.md` | Detailed deployment guide |
| `KEYCLOAK-SSO-SETUP.md` | Complete Keycloak SSO setup guide |
| `commands.txt` | Command reference |

## Architecture

### Development Mode
- SQLite metadata storage
- Single replica
- SimpleCache (no Redis)
- Minimal resource allocation

### Production Mode
- PostgreSQL metadata database
- 2 replicas for high availability
- Persistent storage (5Gi)
- Pod disruption budget
- Health probes and auto-recovery

## Common Commands

### Monitoring
```bash
# Check pods
kubectl get pods -n production

# View logs
kubectl logs -f deployment/superset -n production

# Check resource usage
kubectl top pods -n production
```

### Scaling
```bash
# Scale replicas
kubectl scale deployment superset --replicas=3 -n production

# Update configuration
helm upgrade superset superset/superset \
  --namespace production \
  --values production-superset-values.yaml
```

### Backup
```bash
# Backup PostgreSQL database
POD_NAME=$(kubectl get pods -n production -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD_NAME -n production -- pg_dump -U superset superset > superset-backup.sql
```

### Cleanup
```bash
# Uninstall
helm uninstall superset -n production
kubectl delete -f postgres-production.yaml
kubectl delete namespace production
```

## MySQL Data Sources

To connect MySQL databases in Superset:

1. Access Superset UI
2. Go to Settings → Database Connections
3. Click + Database
4. Select MySQL
5. Enter connection string: `mysql+pymysql://user:password@host:port/database`
6. Test and save

## Keycloak SSO Integration

This deployment includes Keycloak SSO support for secure authentication.

### Quick Start

```bash
# Start Keycloak
docker-compose -f docker-compose-keycloak.yaml up -d

# Access Keycloak Admin Console
# http://localhost:9000 (admin/admin)
```

### Configure SSO

1. Create client in Keycloak:
   - Client ID: `superset`
   - Client type: OpenID Connect
   - Valid redirect URIs: `http://localhost:8081/*`

2. Update Superset environment variables:
   ```bash
   kubectl create secret generic superset-keycloak \
     --from-literal=KEYCLOAK_CLIENT_ID=superset \
     --from-literal=KEYCLOAK_CLIENT_SECRET=<your-secret> \
     --from-literal=KEYCLOAK_DOMAIN=host.docker.internal:9000 \
     -n production

   kubectl set env deployment/superset --from=secret/superset-keycloak -n production
   ```

3. Users will see "Login with Keycloak" button on Superset login page

**For detailed SSO setup instructions, see [KEYCLOAK-SSO-SETUP.md](KEYCLOAK-SSO-SETUP.md)**

## Default Credentials

- Username: `admin`
- Password: `admin`

**Change these in production!**

## Features

- ✅ Embedded dashboards enabled
- ✅ MySQL connectivity (PyMySQL + MySQLdb)
- ✅ PostgreSQL metadata storage (production)
- ✅ SQLite metadata storage (development)
- ✅ Automated database initialization
- ✅ No Redis dependency
- ✅ Iframe embedding support
- ✅ Native filters and cross filters
- ✅ **Keycloak SSO integration** (OAuth 2.0 / OpenID Connect)

## Resource Requirements

### Production
- Web server: 2 replicas, 1 CPU, 2Gi RAM each
- Worker: 1 replica, 500m CPU, 1Gi RAM
- PostgreSQL: 1 replica, 500m CPU, 512Mi RAM
- Storage: 5Gi persistent volume

### Development
- Web server: 1 replica, 500m CPU, 1Gi RAM
- Worker: 1 replica, 250m CPU, 512Mi RAM

## Documentation

For detailed deployment instructions, troubleshooting, and advanced configuration, see:
- [PRODUCTION-DEPLOYMENT-GUIDE.md](PRODUCTION-DEPLOYMENT-GUIDE.md) - Complete deployment guide
- [KEYCLOAK-SSO-SETUP.md](KEYCLOAK-SSO-SETUP.md) - Keycloak SSO integration guide
- [commands.txt](commands.txt) - Command reference

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production
```

### Database connection issues
```bash
kubectl logs job/superset-init-db -n production
kubectl exec deployment/superset -n production -- python -c "import psycopg2; print('OK')"
```

### MySQL driver issues
```bash
kubectl exec deployment/superset -n production -- python -c "import pymysql, MySQLdb; print('Drivers OK')"
```

## Security Notes

For production deployments:
- Change default SECRET_KEY in values files
- Change default admin credentials
- Configure HTTPS/TLS for external access
- Set up proper CORS policies
- Use Kubernetes secrets for sensitive data
- Enable network policies if required
- Regular backups

## License

This deployment configuration is provided as-is. Apache Superset is licensed under the Apache License 2.0.
