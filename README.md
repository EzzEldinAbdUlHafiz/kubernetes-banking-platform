# Kubernetes Banking Platform

A comprehensive banking application deployed on Kubernetes with PostgreSQL replication, Node.js API, and modern web dashboard.

## 📋 Project Overview

This project demonstrates a production-ready banking platform deployed on Kubernetes with high availability, security best practices, and automated setup.

### Key Features

- **Multi-container Microservices Architecture**: Banking API, Dashboard UI, and PostgreSQL database
- **PostgreSQL High Availability**: Primary-replica setup with WAL streaming replication
- **Kubernetes-Native Deployment**: Complete K8s manifests with namespaces, services, deployments, and StatefulSets
- **Security Hardening**: SecurityContext, RBAC (planned), Network Policies, and ConfigMap/Secret management
- **Automated Setup**: Single command deployment with `setup.sh` script
- **Monitoring & Observability**: Probes (startup, readiness, liveness), DaemonSet for logs (planned)
- **Horizontal Pod Autoscaling**: Auto-scaling based on CPU/memory (planned)
- **Production-Ready**: Resource limits, node affinity/anti-affinity, tolerations

## 🏗️ Architecture

### Components

1. **PostgreSQL StatefulSet** (`03-postgres-statefulset.yaml`)
   - 2-replica PostgreSQL cluster with primary-replica streaming replication
   - Node affinity to `high-memory` labeled nodes
   - Pod anti-affinity for high availability
   - Persistent Volume Claims (5Gi each)
   - Custom init script for replication setup

2. **Banking API Deployment** (`04-api-deployment.yaml`)
   - Node.js/Express application with PostgreSQL connection pooling
   - 2 replicas with pod anti-affinity
   - Environment variables from ConfigMap and Secret
   - Health checks (`/health`, `/ready` endpoints)
   - SecurityContext with non-root user and read-only root filesystem

3. **Banking Dashboard Deployment** (`05-dashboard-deployment.yaml`)
   - Static HTML/JavaScript dashboard served by Nginx
   - 1 replica with node affinity
   - Modern UI with real-time updates
   - SecurityContext with dropped capabilities except NET_BIND_SERVICE

4. **Network & Service Layer**
   - Namespace isolation (`banking` namespace)
   - Headless service for PostgreSQL StatefulSet
   - ClusterIP services for API and Dashboard
   - Ingress with path-based routing (`/api` → API, `/` → Dashboard)
   - Rate limiting annotations on Ingress

### Data Flow

```
Users → Ingress → (/) → Dashboard Service → Dashboard Pod
                  (/api) → API Service → API Pods → PostgreSQL Primary → PostgreSQL Replica
```

## 📁 Project Structure

```
kubernetes-banking-platform/
├── README.md                          # This file
├── setup.sh                           # Main deployment script
├── app/
│   ├── banking-api/
│   │   ├── app.js                     # Node.js Express API application
│   │   ├── Dockerfile                 # Multi-stage Docker build
│   │   ├── package.json               # Node dependencies
│   │   └── .dockerignore              # Docker ignore file
│   └── banking-dashboard/
│       ├── index.html                 # Dashboard HTML/JS/CSS
│       ├── Dockerfile                 # Nginx-based Docker image
│       └── nginx.conf                 # Nginx configuration
├── k8s/
│   ├── 00-namespace.yaml              # Banking namespace
│   ├── 01-configmap.yaml              # Application configuration
│   ├── 02-secret.yaml                 # Database credentials
│   ├── 03-postgres-statefulset.yaml   # PostgreSQL StatefulSet
│   ├── 04-api-deployment.yaml         # Banking API Deployment
│   ├── 05-dashboard-deployment.yaml   # Dashboard Deployment
│   ├── 06-services.yaml               # Kubernetes Services
│   ├── 07-ingress.yaml                # Ingress configuration
│   ├── 08-hpa-vpa.yaml                # Horizontal/Vertical Pod Autoscaling
│   ├── 09-rbac.yaml                   # Role-Based Access Control
│   ├── 10-networkpolicy.yaml          # Network Policies
│   ├── 11-daemonset-fluentd.yaml      # Logging DaemonSet
│   └── scripts/
│       └── postgres-init.sh           # PostgreSQL replication initialization
```

## 🚀 Quick Start

### Prerequisites

- Docker
- kubectl
- Minikube (or any Kubernetes cluster)
- Internet access for pulling container images

### Automated Deployment

```bash
# Make setup script executable
chmod +x setup.sh

# Full setup (creates minikube cluster + deploys everything)
./setup.sh full-setup

# Or deploy to existing cluster
./setup.sh setup
```

### Manual Deployment Steps

1. **Start Minikube Cluster**
   ```bash
   minikube start --driver=docker --nodes=3 --cni=calico
   minikube addons enable ingress
   minikube addons enable metrics-server
   ```

2. **Configure Node Labels and Taints**
   ```bash
   # Control plane node
   kubectl taint nodes minikube node-role.kubernetes.io/control-plane=:NoSchedule --overwrite
   
   # Worker nodes
   kubectl label node minikube-m02 type=high-memory --overwrite
   kubectl label node minikube-m03 type=high-memory --overwrite
   kubectl taint nodes minikube-m02 database-only=true:NoSchedule --overwrite
   kubectl taint nodes minikube-m03 database-only=true:NoSchedule --overwrite
   ```

3. **Build and Push Docker Images**
   ```bash
   # Build API image
   docker build -t yourusername/banking-api:v1.0 app/banking-api/
   docker push yourusername/banking-api:v1.0
   
   # Build Dashboard image
   docker build -t yourusername/banking-dashboard:v1.0 app/banking-dashboard/
   docker push yourusername/banking-dashboard:v1.0
   ```

4. **Apply Kubernetes Manifests**
   ```bash
   # Create namespace
   kubectl apply -f k8s/00-namespace.yaml
   
   # Create ConfigMap and Secret
   kubectl create configmap postgres-init-script \
     --from-file=init.sh=k8s/scripts/postgres-init.sh \
     --namespace=banking --dry-run=client -o yaml | kubectl apply -f -
   kubectl apply -f k8s/01-configmap.yaml
   kubectl apply -f k8s/02-secret.yaml
   
   # Apply remaining manifests in order
   kubectl apply -f k8s/06-services.yaml      # Services first
   kubectl apply -f k8s/03-postgres-statefulset.yaml
   kubectl apply -f k8s/04-api-deployment.yaml
   kubectl apply -f k8s/05-dashboard-deployment.yaml
   kubectl apply -f k8s/07-ingress.yaml
   
   # Wait for deployments
   kubectl rollout status statefulset/postgres-db -n banking --timeout=300s
   kubectl rollout status deployment/banking-api -n banking --timeout=180s
   kubectl rollout status deployment/banking-dashboard -n banking --timeout=180s
   ```

5. **Configure /etc/hosts**
   ```bash
   echo "$(minikube ip) banking.local" | sudo tee -a /etc/hosts
   ```

## 🔧 Configuration

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `DB_HOST_PRIMARY` | Primary PostgreSQL pod DNS | `postgres-db-0.postgres-db.banking.svc.cluster.local` |
| `DB_HOST_REPLICA` | Replica PostgreSQL pod DNS | `postgres-db-1.postgres-db.banking.svc.cluster.local` |
| `DB_PORT` | PostgreSQL port | `5432` |
| `DB_NAME` | Database name | `bankingdb` |
| `DB_USER` | Application database user | `bankuser` |
| `DB_PASSWORD` | Database password | `postgres` (via Secret) |
| `API_LOG_LEVEL` | API logging level | `info` |
| `MAX_TRANSACTION_LIMIT` | Maximum transaction amount | `50000` |
| `PORT` | API server port | `3000` |

### Node Configuration

- **Control Plane Node**: Tainted with `node-role.kubernetes.io/control-plane=:NoSchedule`
- **Worker Nodes**: Labeled with `type=high-memory`, tainted with `database-only=true:NoSchedule`
- **Pod Placement**: 
  - PostgreSQL pods tolerate `database-only` taint
  - All pods have node affinity to `high-memory` nodes
  - Anti-affinity rules prevent multiple PostgreSQL or API pods on same node

### Resources and Limits

- **PostgreSQL**: Request 1Gi memory, Limit 2Gi memory
- **Banking API**: Request 128Mi memory / 100m CPU, Limit 256Mi memory / 500m CPU
- **Dashboard**: Request 128Mi memory / 200m CPU, Limit 128Mi memory / 200m CPU

## 🌐 Accessing the Application

### URLs
- **Dashboard**: http://banking.local
- **API**: http://banking.local/api/accounts
- **API Health Check**: http://banking.local/api/health
- **API Readiness**: http://banking.local/api/ready
- **API Statistics**: http://banking.local/api/stats

### Port Forwarding
```bash
# API service
kubectl port-forward svc/banking-api-service 3000:3000 -n banking

# Dashboard service  
kubectl port-forward svc/banking-dashboard-service 8080:80 -n banking
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/accounts` | List all bank accounts |
| POST | `/api/accounts` | Create new account |
| GET | `/api/transactions` | List recent transactions |
| POST | `/api/transactions` | Transfer money between accounts |
| GET | `/api/stats` | Get platform statistics |
| GET | `/health` | Health check endpoint |
| GET | `/ready` | Readiness probe endpoint |

## 🔍 Monitoring & Debugging

### Check Deployment Status
```bash
# View all resources
kubectl get all -n banking

# Check pod status
kubectl get pods -n banking -o wide

# View logs
kubectl logs -l app=banking-api -n banking --tail=50
kubectl logs -l app=postgres-db -n banking --tail=50

# Describe specific pod
kubectl describe pod/postgres-db-0 -n banking
```

### Verify PostgreSQL Replication
```bash
# Check replication status
kubectl exec -it postgres-db-0 -n banking -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
kubectl exec -it postgres-db-1 -n banking -- psql -U postgres -c "SELECT pg_is_in_recovery();"

# Check data consistency
kubectl exec -it postgres-db-0 -n banking -- psql -U postgres -d bankingdb -c "SELECT COUNT(*) FROM accounts;"
kubectl exec -it postgres-db-1 -n banking -- psql -U postgres -d bankingdb -c "SELECT COUNT(*) FROM accounts;"
```

### Test Database Connectivity
```bash
# From API pod
kubectl exec -it deployment/banking-api -n banking -- sh
# Inside container:
node -e "
const { Pool } = require('pg');
const pool = new Pool({
  host: process.env.DB_HOST_PRIMARY,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT
});
pool.query('SELECT 1', (err, res) => console.log(err || 'Connected'))
"
```

## 🧪 Testing the Application

### Create Account via API
```bash
# Direct to service
curl -X POST http://banking.local/api/accounts \
  -H "Content-Type: application/json" \
  -d '{"owner": "Test User", "initial_balance": 1000}'

# Via port-forward
curl -X POST http://localhost:3000/api/accounts \
  -H "Content-Type: application/json" \
  -d '{"owner": "Test User", "initial_balance": 1000}'
```

### Transfer Funds
```bash
curl -X POST http://banking.local/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"from_account": 1, "to_account": 2, "amount": 500, "note": "Test transfer"}'
```

### View Data
```bash
# List accounts
curl http://banking.local/api/accounts

# List transactions
curl http://banking.local/api/transactions

# Get statistics
curl http://banking.local/api/stats
```

## 🛠️ Development

### Building Images Locally

```bash
# Build API
cd app/banking-api
docker build -t banking-api:local .

# Build Dashboard
cd ../banking-dashboard
docker build -t banking-dashboard:local .
```

### Updating Configuration

1. **ConfigMap Updates**: Modify `k8s/01-configmap.yaml` and apply:
   ```bash
   kubectl apply -f k8s/01-configmap.yaml
   kubectl rollout restart deployment/banking-api -n banking
   ```

2. **Secret Updates**: Modify `k8s/02-secret.yaml` and apply:
   ```bash
   kubectl apply -f k8s/02-secret.yaml
   kubectl rollout restart deployment/banking-api -n banking
   kubectl rollout restart statefulset/postgres-db -n banking
   ```

### Scaling

```bash
# Scale API replicas
kubectl scale deployment/banking-api --replicas=3 -n banking

# Scale PostgreSQL replicas (requires updating StatefulSet manifest)
kubectl patch statefulset postgres-db -n banking -p '{"spec":{"replicas":3}}'
```

## 🔒 Security Considerations

### Current Implementation
- Non-root user execution (PostgreSQL: UID 70, API: UID 1000, Dashboard: UID 101)
- Read-only root filesystem for API containers
- Dropped Linux capabilities
- Encrypted password transmission for PostgreSQL replication
- Environment variables for sensitive data (not in images)

### Planned Security Enhancements
- RBAC roles and service accounts (`09-rbac.yaml`)
- Network policies to restrict traffic (`10-networkpolicy.yaml`)  
- TLS/SSL termination at ingress
- Secret management with external providers (Hashicorp Vault, Azure Key Vault)
- Image scanning in CI/CD pipeline

## 📈 Performance Considerations

### Optimizations Implemented
- **Connection Pooling**: PostgreSQL connection pools in API (max: 10 connections each)
- **Read/Write Separation**: Read operations use replica, writes use primary
- **Pod Anti-Affinity**: Prevents single node failure from taking down all replicas
- **Resource Limits**: Prevents resource starvation
- **Node Affinity**: Ensures pods run on appropriate hardware

### Monitoring & Scaling
- **Horizontal Pod Autoscaling** (HPA): Planned via `08-hpa-vpa.yaml`
- **Vertical Pod Autoscaling** (VPA): Planned via `08-hpa-vpa.yaml`
- **Custom Metrics**: API response times, transaction throughput
- **Alerting**: Planned integration with Prometheus/Grafana

## 🧹 Cleanup

### Using Script
```bash
./setup.sh cleanup
```

### Manual Cleanup
```bash
# Delete entire namespace
kubectl delete namespace banking

# Delete Minikube cluster
minikube delete

# Remove /etc/hosts entry
sudo sed -i '/banking.local/d' /etc/hosts
```

## 🐛 Troubleshooting

### Common Issues

1. **PostgreSQL pods not starting**
   ```bash
   # Check initialization logs
   kubectl logs postgres-db-0 -n banking
   
   # Check PVC status
   kubectl get pvc -n banking
   ```

2. **API not connecting to database**
   ```bash
   # Check DNS resolution
   kubectl exec deployment/banking-api -n banking -- nslookup postgres-db.banking.svc.cluster.local
   
   # Check environment variables
   kubectl exec deployment/banking-api -n banking -- env | grep DB_
   ```

3. **Ingress not working**
   ```bash
   # Check ingress controller
   minikube addons list | grep ingress
   
   # Check ingress resource
   kubectl get ingress -n banking
   kubectl describe ingress banking-ingress -n banking
   ```

4. **Resources stuck in Pending state**
   ```bash
   # Check node resources
   kubectl describe nodes
   
   # Check events
   kubectl get events -n banking --sort-by='.lastTimestamp'
   ```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `./setup.sh full-setup`
5. Submit a pull request

## 📄 License

This project is for educational purposes. Feel free to use and modify as needed.

---

## 🚀 Quick Reference

| Command | Purpose |
|---------|---------|
| `./setup.sh full-setup` | Complete deployment from scratch |
| `./setup.sh setup` | Deploy to existing cluster |
| `./setup.sh configure-nodes` | Label and taint nodes |
| `./setup.sh images` | Build and push Docker images |
| `./setup.sh deploy` | Apply Kubernetes manifests |
| `./setup.sh status` | Show deployment status |
| `./setup.sh access` | Show access information |
| `./setup.sh cleanup` | Remove resources |

For detailed documentation, refer to individual YAML files and the setup script.
