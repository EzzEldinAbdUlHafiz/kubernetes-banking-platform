# Kubernetes Banking Platform

A comprehensive banking application deployed on Kubernetes with PostgreSQL replication, Node.js API, and modern web dashboard.

![Architecture Diagram](https://raw.githubusercontent.com/ahmedabdulhafiz/kubernetes-banking-platform/main/docs/architecture.png)

## 📋 Project Overview

This project demonstrates a production-ready banking platform deployed on Kubernetes with high availability, security best practices, and automated setup.

### Key Features

- **Multi-tier Architecture**: Banking API (Node.js), Dashboard UI (HTML/JS), and PostgreSQL database
- **High Availability Database**: PostgreSQL primary-replica setup with streaming replication
- **Kubernetes-Native Deployment**: Production-grade manifests with namespaces, services, deployments, and StatefulSets
- **Security Best Practices**: SecurityContext, RBAC, Network Policies, and ConfigMap/Secret management
- **Automated Setup**: Single command deployment with `setup.sh` script
- **Monitoring & Observability**: Health checks, readiness/liveness probes, and logging
- **Auto-scaling**: Horizontal Pod Autoscaling based on CPU/memory utilization
- **Production-Ready**: Resource limits, node affinity/anti-affinity, tolerations

## 🏗️ Architecture

### Components

1. **PostgreSQL StatefulSet** (`03-postgres-statefulset.yaml`)
   - 2-replica PostgreSQL cluster with primary-replica streaming replication
   - Node affinity to `high-memory` labeled nodes
   - Pod anti-affinity for high availability
   - Persistent Volume Claims (5Gi each)
   - Custom setup script for replication setup

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

## 🚀 Quick Start

### Prerequisites

- Docker
- kubectl
- Minikube (or any Kubernetes cluster)
- Internet access for pulling container images

### One-Command Deployment

```bash
# Make setup script executable
chmod +x setup.sh

# Full setup (creates minikube cluster + deploys everything)
./setup.sh full-setup
```

### Manual Deployment Steps

```bash
# Deploy to existing cluster
./setup.sh setup
```

### Deployment Options

The setup script provides several options for deployment:

1. `full-setup`: Creates a new minikube cluster with 3 nodes and deploys the entire application
2. `setup`: Deploys the application to an existing cluster
3. `configure-nodes`: Configures node labels and taints only
4. `images`: Builds and pushes Docker images only
5. `deploy`: Applies Kubernetes manifests only
6. `status`: Shows deployment status
7. `access`: Displays access information
8. `cleanup`: Removes deployed resources

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
   kubectl create configmap postgres-setup-script \
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

The application configuration is managed through ConfigMaps and Secrets:

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

### Database Schema

The application uses two main tables:

1. **Accounts Table**
   ```sql
   CREATE TABLE accounts (
     id          SERIAL PRIMARY KEY,
     owner       VARCHAR(100) NOT NULL,
     balance     DECIMAL(12,2) DEFAULT 0.00,
     created_at  TIMESTAMPTZ DEFAULT NOW()
   );
   ```

2. **Transactions Table**
   ```sql
   CREATE TABLE transactions (
     id           SERIAL PRIMARY KEY,
     from_account INT REFERENCES accounts(id),
     to_account   INT REFERENCES accounts(id),
     amount       DECIMAL(12,2) NOT NULL,
     note         VARCHAR(200),
     status       VARCHAR(20) DEFAULT 'completed',
     created_at   TIMESTAMPTZ DEFAULT NOW()
   );
   ```

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

### Access from Windows Host

If running Kubernetes in a Linux VM and accessing from a Windows host, see [access_from_win.md](access_from_win.md) for detailed instructions on configuring cross-platform access.

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

### Dashboard Features

The web dashboard provides a user-friendly interface to:

- View account balances and details
- See recent transactions
- Create new accounts
- Transfer money between accounts
- Monitor platform statistics in real-time

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

### Automated Testing

Run the provided test script to verify the application:

```bash
# Execute the test script (if available)
./test.sh
```

Or manually verify core functionality:

1. Check API health: `curl http://banking.local/api/health`
2. Create a test account: `curl -X POST http://banking.local/api/accounts -H "Content-Type: application/json" -d '{"owner": "John Doe", "initial_balance": 5000}'`
3. Verify account creation: `curl http://banking.local/api/accounts`
4. Transfer funds: `curl -X POST http://banking.local/api/transactions -H "Content-Type: application/json" -d '{"from_account": 1, "to_account": 2, "amount": 1000}'`
5. Check transactions: `curl http://banking.local/api/transactions`

## 🛠️ Development

### Local Development Setup

1. Install Node.js dependencies for the API:
```bash
cd app/banking-api
npm install
```

2. Run the API locally (requires PostgreSQL):
```bash
# Set environment variables
export DB_HOST_PRIMARY=localhost
export DB_HOST_REPLICA=localhost
export DB_PORT=5432
export DB_NAME=bankingdb
export DB_USER=bankuser
export DB_PASSWORD=yourpassword

# Start the API
npm start
```

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

### Debugging

```bash
# View logs for a specific component
kubectl logs -l app=banking-api -n banking --follow

# Execute commands in a running container
kubectl exec -it deployment/banking-api -n banking -- /bin/sh

# Port forward to access services directly
kubectl port-forward svc/banking-api-service 3000:3000 -n banking
```

## 🔒 Security Considerations

### Current Implementation
- Non-root user execution (PostgreSQL: UID 70, API: UID 1000, Dashboard: UID 101)
- Read-only root filesystem for API containers
- Dropped Linux capabilities
- Encrypted password transmission for PostgreSQL replication
- Environment variables for sensitive data (not in images)
- Secrets stored separately from code using Kubernetes Secrets
- Network policies to restrict inter-pod communication
- RBAC roles and service accounts for fine-grained access control

### Security Best Practices

1. **Container Security**:
   - Minimal base images (Alpine Linux)
   - Non-root user execution
   - Read-only root filesystem for application containers
   - Dropped unnecessary Linux capabilities

2. **Network Security**:
   - Pod anti-affinity to distribute workloads
   - Network policies to restrict traffic
   - Service mesh readiness (Istio/Linkerd compatible)

3. **Data Security**:
   - Secrets management with Kubernetes Secrets
   - Encrypted communication between components
   - Secure configuration management

### Planned Security Enhancements
- Mutual TLS authentication between services
- External secret management (Hashicorp Vault, Azure Key Vault)
- Image signing and verification in CI/CD pipeline
- Enhanced network encryption with WireGuard or similar
- Advanced audit logging and monitoring

## 📈 Performance Considerations

### Optimizations Implemented
- **Connection Pooling**: PostgreSQL connection pools in API (max: 10 connections each)
- **Read/Write Separation**: Read operations use replica, writes use primary
- **Pod Anti-Affinity**: Prevents single node failure from taking down all replicas
- **Resource Limits**: Prevents resource starvation
- **Node Affinity**: Ensures pods run on appropriate hardware
- **Startup/Readiness/Liveness Probes**: Ensures proper container lifecycle management
- **Efficient Database Queries**: Indexes and optimized SQL queries

### Monitoring & Scaling
- **Horizontal Pod Autoscaling** (HPA): Automatically scales API pods based on CPU/memory usage
- **Vertical Pod Autoscaling** (VPA): Recommends/updates resource requests and limits
- **Custom Metrics**: API response times, transaction throughput
- **Logging**: Fluentd DaemonSet for centralized log collection
- **Alerting**: Integration ready with Prometheus/Grafana

### Performance Testing

To evaluate performance:

1. Load test the API using tools like Apache Bench or Artillery:
```bash
ab -n 1000 -c 10 http://banking.local/api/accounts
```

2. Monitor resource usage:
```bash
kubectl top pods -n banking
```

3. Check HPA status:
```bash
kubectl get hpa -n banking
```

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
   
   # Check StatefulSet status
   kubectl describe statefulset postgres-db -n banking
   ```

2. **API not connecting to database**
   ```bash
   # Check DNS resolution
   kubectl exec deployment/banking-api -n banking -- nslookup postgres-db.banking.svc.cluster.local
   
   # Check environment variables
   kubectl exec deployment/banking-api -n banking -- env | grep DB_
   
   # Test database connectivity directly
   kubectl exec deployment/banking-api -n banking -- sh -c "nc -zv postgres-db.banking.svc.cluster.local 5432"
   ```

3. **Ingress not working**
   ```bash
   # Check ingress controller
   minikube addons list | grep ingress
   
   # Check ingress resource
   kubectl get ingress -n banking
   kubectl describe ingress banking-ingress -n banking
   
   # Verify /etc/hosts entry
   grep banking.local /etc/hosts
   ```

4. **Resources stuck in Pending state**
   ```bash
   # Check node resources
   kubectl describe nodes
   
   # Check events
   kubectl get events -n banking --sort-by='.lastTimestamp'
   
   # Check pod scheduling issues
   kubectl describe pod <pod-name> -n banking
   ```

### Diagnostic Commands

```bash
# Check overall cluster status
kubectl cluster-info

# View all resources in the banking namespace
kubectl get all -n banking

# Check pod logs for errors
kubectl logs -l app=banking-api -n banking --tail=100

# Check service endpoints
kubectl get endpoints -n banking

# Verify ConfigMaps and Secrets
kubectl get configmap,secret -n banking
```

## 🤝 Contributing

We welcome contributions to enhance the banking platform! Here's how you can contribute:

1. Fork the repository on GitHub
2. Create a feature branch for your changes
3. Implement your changes or new features
4. Test thoroughly with `./setup.sh full-setup`
5. Ensure all security best practices are followed
6. Submit a pull request with a clear description of your changes

### Areas for Contribution

- Additional API endpoints (loan processing, interest calculation, etc.)
- Enhanced dashboard features (charts, graphs, reporting)
- Improved security measures
- Additional database implementations
- Performance optimizations
- Documentation improvements
- Test coverage expansion

## 📄 License

This project is for educational purposes. Feel free to use and modify as needed for learning and development. Commercial use should be properly attributed.

---

## 📞 Support

For issues, questions, or feedback, please:
1. Open an issue on GitHub
2. Contact the maintainer directly
3. Refer to the troubleshooting section for common problems

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

## 📊 Project Status

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.20%2B-blue)](https://kubernetes.io/)
[![Platform](https://img.shields.io/badge/platform-minikube-orange)](https://minikube.sigs.k8s.io/)

> **Note**: This project is designed for educational and demonstration purposes. It showcases modern cloud-native application development practices, but may require additional hardening for production use.
