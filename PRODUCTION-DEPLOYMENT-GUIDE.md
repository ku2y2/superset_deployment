# Apache Superset Production Deployment Guide

Complete guide for deploying Apache Superset in production with PostgreSQL metadata storage and MySQL data connectivity.

## 🎯 **What This Deployment Provides**

✅ **Production-Ready Apache Superset** with PostgreSQL metadata storage
✅ **MySQL Connectivity** for data sources (PyMySQL + MySQLdb compatibility)
✅ **Embedded Dashboards** ready for iframe integration
✅ **Automated Database Initialization** with admin user creation
✅ **High Availability** configuration with multiple replicas
✅ **Zero Manual Steps** - fully automated deployment

## 📋 **Prerequisites**

- Kubernetes cluster (Minikube, EKS, GKE, AKS, etc.)
- kubectl configured and connected to your cluster
- Helm 3.x installed
- Docker installed locally

## 🚀 **Step-by-Step Deployment**

### **Step 1: Build Custom Docker Image**

```bash
# Navigate to deployment directory
cd /Users/kundankumar/superset_deployment

# Build custom Superset image with MySQL drivers
docker build -t superset-mysql:latest .

# Load image into Minikube (if using Minikube)
minikube image load superset-mysql:latest

# Verify image is available
minikube image ls | grep superset-mysql
```

### **Step 2: Setup Kubernetes Environment**

```bash
# Create production namespace
kubectl create namespace production

# Verify namespace creation
kubectl get namespaces | grep production
```

### **Step 3: Add Superset Helm Repository**

```bash
# Add official Superset Helm repository
helm repo add superset https://apache.github.io/superset

# Update Helm repositories
helm repo update

# Verify Superset chart is available
helm search repo superset/superset
```

### **Step 4: Deploy PostgreSQL Database**

```bash
# Deploy PostgreSQL for metadata storage
kubectl apply -f postgres-production.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=postgresql -n production --timeout=120s

# Verify PostgreSQL is running
kubectl get pods -n production | grep postgresql
```

### **Step 5: Deploy Superset**

```bash
# Deploy Superset with production configuration
helm install superset superset/superset \
  --namespace production \
  --values production-superset-values.yaml

# Monitor deployment progress
kubectl get pods -n production -w
```

### **Step 6: Verify Deployment**

```bash
# Check all pods are running
kubectl get pods -n production

# Expected output:
# NAME                               READY   STATUS      RESTARTS   AGE
# postgresql-5cfc9b76b8-zxswv        1/1     Running     0          30m
# superset-68f7d558bd-w4bmx          1/1     Running     0          10m
# superset-init-db-z48fp             0/1     Completed   0          10m

# Check logs to ensure everything is working
kubectl logs deployment/superset -n production --tail=20
```

### **Step 7: Access Superset**

```bash
# Port forward to access Superset locally
kubectl port-forward service/superset 8081:8088 -n production

# Access Superset at: http://localhost:8081
# Default credentials:
# Username: admin
# Password: admin
```

## 🔧 **Configuration Details**

### **Database Configuration**
- **Metadata Storage**: PostgreSQL (`superset-postgresql:5432`)
- **Database**: `superset`
- **User**: `superset`
- **Password**: `superset`

### **Resource Allocation**
- **Web Server**: 2 replicas, 1 CPU, 2Gi RAM each
- **PostgreSQL**: 1 replica, 500m CPU, 512Mi RAM
- **Storage**: 5Gi persistent volume for PostgreSQL

### **Features Enabled**
- ✅ **Embedded Dashboards** (`EMBEDDED_SUPERSET = True`)
- ✅ **Native Filters** and Cross Filters
- ✅ **SQL Lab** without Redis dependency
- ✅ **MySQL Support** (PyMySQL + MySQLdb compatibility)
- ✅ **Security Headers** (TALISMAN configuration)

## 🗄️ **Adding MySQL Data Sources**

1. Access Superset at `http://localhost:8081`
2. Login with `admin/admin`
3. Go to **Settings** → **Database Connections**
4. Click **+ Database**
5. Select **MySQL** from dropdown
6. Enter connection details:
   - **Display Name**: `Your Database Name`
   - **SQLAlchemy URI**: `mysql+pymysql://username:password@host:port/database`
   - **Example**: `mysql+pymysql://root:debezium@192.168.1.4:3308/tracking_live`
7. Click **Test Connection**
8. Click **Connect** to save

## 📊 **Monitoring and Maintenance**

### **Health Checks**
```bash
# Check pod health
kubectl get pods -n production

# Check service status
kubectl get services -n production

# Monitor resource usage
kubectl top pods -n production

# View recent events
kubectl get events -n production --sort-by='.lastTimestamp'
```

### **Scaling Operations**
```bash
# Scale web server replicas
kubectl scale deployment superset --replicas=3 -n production

# Update deployment with new configuration
helm upgrade superset superset/superset \
  --namespace production \
  --values production-superset-values.yaml
```

### **Log Monitoring**
```bash
# View Superset application logs
kubectl logs -f deployment/superset -n production

# View PostgreSQL logs
kubectl logs -f deployment/postgresql -n production

# View initialization logs
kubectl logs job/superset-init-db -n production
```

## 🔄 **Backup and Recovery**

### **Database Backup**
```bash
# Get PostgreSQL pod name
POD_NAME=$(kubectl get pods -n production -l app=postgresql -o jsonpath='{.items[0].metadata.name}')

# Create database backup
kubectl exec $POD_NAME -n production -- pg_dump -U superset superset > superset-backup.sql

# Restore from backup
cat superset-backup.sql | kubectl exec -i $POD_NAME -n production -- psql -U superset superset
```

### **Configuration Backup**
```bash
# Backup Helm values
cp production-superset-values.yaml superset-config-backup-$(date +%Y%m%d).yaml

# Backup PostgreSQL configuration
cp postgres-production.yaml postgres-config-backup-$(date +%Y%m%d).yaml
```

## 🚨 **Troubleshooting**

### **Common Issues**

**1. Pods Stuck in Pending:**
```bash
kubectl describe pod <pod-name> -n production
# Check for resource constraints or node issues
```

**2. PostgreSQL Connection Issues:**
```bash
# Test network connectivity
kubectl exec deployment/superset -n production -- python -c "
import socket
s = socket.socket()
s.settimeout(5)
result = s.connect_ex(('superset-postgresql', 5432))
print('PostgreSQL connectivity:', 'SUCCESS' if result == 0 else 'FAILED')
s.close()
"
```

**3. Memory Issues (Worker OOMKilled):**
```bash
# Check resource usage
kubectl top pods -n production

# Increase worker memory in production-superset-values.yaml:
# supersetWorker.resources.limits.memory: "2Gi"
```

**4. Init Job Failed:**
```bash
# Check init job logs
kubectl logs job/superset-init-db -n production

# Delete failed job and redeploy
kubectl delete job superset-init-db -n production
helm upgrade superset superset/superset --namespace production --values production-superset-values.yaml
```

## 🔐 **Security Considerations**

### **Production Security Checklist**
- [ ] Change default admin credentials
- [ ] Configure proper SECRET_KEY for production
- [ ] Set up HTTPS/TLS for external access
- [ ] Configure proper CORS settings
- [ ] Set up monitoring and alerting
- [ ] Regular backup procedures
- [ ] Resource quotas and limits
- [ ] Network policies (if required)

### **Recommended Changes for Production**
```yaml
# In production-superset-values.yaml, update:
configOverrides:
  secret: |
    # Generate new secret key
    SECRET_KEY = 'your-production-secret-key-here'

    # Configure CORS for your domain
    CORS_OPTIONS = {
        'origins': ['https://yourdomain.com'],
        'supports_credentials': True
    }
```

## 🧹 **Cleanup**

```bash
# Uninstall Superset
helm uninstall superset -n production

# Delete PostgreSQL
kubectl delete -f postgres-production.yaml

# Delete namespace (removes all resources)
kubectl delete namespace production

# Remove Docker image (if needed)
docker rmi superset-mysql:latest
```

## 📁 **File Structure**

```
superset_deployment/
├── Dockerfile                          # Custom image with MySQL drivers
├── production-superset-values.yaml     # Main production configuration
├── postgres-production.yaml            # PostgreSQL deployment
├── PRODUCTION-DEPLOYMENT-GUIDE.md      # This guide
├── commands.txt                        # Command reference
└── dev-superset-values.yaml           # Development configuration
```

## ✅ **Deployment Verification Checklist**

- [ ] Custom Docker image built and loaded into Minikube
- [ ] Production namespace created
- [ ] PostgreSQL deployed and running
- [ ] Superset deployed successfully
- [ ] All pods are in Running/Completed status
- [ ] Superset accessible via port-forward
- [ ] Admin login working (admin/admin)
- [ ] PostgreSQL connectivity verified
- [ ] MySQL drivers available for data connections
- [ ] Embedded dashboard features enabled

## 🎉 **Success Indicators**

When deployment is successful, you should see:

```bash
$ kubectl get pods -n production
NAME                               READY   STATUS      RESTARTS   AGE
postgresql-5cfc9b76b8-zxswv        1/1     Running     0          30m
superset-68f7d558bd-w4bmx          1/1     Running     0          10m
superset-init-db-z48fp             0/1     Completed   0          10m
```

- **PostgreSQL**: Running with persistent storage
- **Superset Main**: Running and responding to health checks
- **Init Job**: Completed successfully
- **Web Interface**: Accessible at http://localhost:8081
- **Admin Access**: Working with admin/admin
- **MySQL Connectivity**: Ready for data source connections

Your production Apache Superset deployment is now ready for enterprise use! 🚀