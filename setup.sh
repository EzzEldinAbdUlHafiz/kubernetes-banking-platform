#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"
APP_DIR="$SCRIPT_DIR/app"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "${BLUE}[STEP]${NC} $1"; }

print_header() {
  echo ""
  echo "========================================"
  echo " $1"
  echo "========================================"
}

is_file_empty() {
  [[ ! -s "$1" ]] && return 0 || return 1
}

# ── Prerequisites ──────────────────────────────────────────
check_prerequisites() {
  print_header "Checking Prerequisites"
  local missing=()

  for cmd in docker kubectl minikube; do
    if ! command -v "$cmd" &> /dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    echo "Please install the missing tools and try again."
    exit 1
  fi

  log_info "All prerequisites satisfied"
}

# ── Minikube Full Setup ────────────────────────────────────
full_setup() {
  print_header "Full Minikube Setup"
  log_info "Setting up minikube with banking platform configuration:"
  log_info "  Driver:  docker"
  log_info "  Nodes:   3 (1 control plane + 2 workers)"
  log_info "  CNI:     Calico"
  log_info "  Addons:  ingress, metrics-server, csi-hostpath-driver"
  echo ""

  read -p "Continue? (y/N): " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && { log_info "Aborted."; exit 0; }

  if minikube status &> /dev/null; then
    log_warn "Minikube is already running."
    read -p "Delete and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log_info "Deleting existing minikube..."
      minikube delete
    else
      log_info "Using existing minikube cluster."
      return 0
    fi
  fi

  log_info "Starting minikube..."
  minikube start \
    --driver=docker \
    --nodes=3 \
    --cni=calico

  log_info "Enabling addons..."
  minikube addons enable ingress
  minikube addons enable metrics-server
  minikube addons enable csi-hostpath-driver

  log_info "Minikube full setup complete"
}

# ── Init Minikube (existing cluster) ──────────────────────
init_minikube() {
  print_header "Initializing Minikube"

  if minikube status &> /dev/null; then
    log_warn "Minikube is already running"
    read -p "Restart minikube? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log_info "Stopping existing minikube..."
      minikube stop
      minikube delete
    else
      log_info "Using existing minikube"
      return 0
    fi
  fi

  log_info "Starting minikube..."
  minikube start \
    --driver=docker \
    --nodes=3 \
    --cni=calico

  log_info "Enabling addons..."
  minikube addons enable ingress
  minikube addons enable metrics-server
  minikube addons enable csi-hostpath-driver

  log_info "Minikube is ready"
}

# ── Node Configuration ─────────────────────────────────────
configure_nodes() {
  print_header "Configuring Node Taints and Labels"
  sleep 5

  local nodes=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
  local worker_nodes_configured=0

  # Taint control plane
  for node in "${nodes[@]}"; do
    if [[ "$node" == "minikube" ]]; then
      log_info "Tainting control plane node: $node"
      kubectl taint nodes "$node" \
        node-role.kubernetes.io/control-plane=:NoSchedule \
        --overwrite 2>/dev/null || true
    fi
  done

  # Label and taint all worker nodes
  for node in "${nodes[@]}"; do
    if [[ "$node" != "minikube" ]]; then
      log_info "Configuring worker node: $node"
      kubectl label node "$node" type=high-memory --overwrite
      kubectl taint nodes "$node" database-only=true:NoSchedule --overwrite 2>/dev/null || true
      worker_nodes_configured=$((worker_nodes_configured + 1))
    fi
  done

  if [[ $worker_nodes_configured -eq 0 ]]; then
    log_warn "No worker nodes found. Is your cluster running with multiple nodes?"
    exit 1
  fi

  log_info "Configured $worker_nodes_configured worker node(s)"

  # Verify
  echo ""
  log_info "Node summary:"
  kubectl get nodes -o wide
  echo ""
  kubectl describe nodes | grep -E "(Name:|Taints:|Labels:)" || true
}

# ── Image Handling ─────────────────────────────────────────
handle_api_image() {
  print_header "Banking API Image"
  echo "1) Build and push to Docker Hub"
  echo "2) Use existing image from Docker Hub"
  echo "3) Skip"
  read -p "Choose option [1-3]: " -n 1 -r
  echo

  case $REPLY in
    1)
      read -p "Enter your Docker Hub username: " dh_user
      local image="$dh_user/banking-api:v1.0"
      log_info "Building $image..."
      docker build -t "$image" "$APP_DIR/banking-api"
      log_info "Pushing $image..."
      docker push "$image"
      export API_IMAGE="$image"
      ;;
    2)
      read -p "Enter Docker Hub image (e.g., username/banking-api:v1.0): " hub_image
      [[ -z "$hub_image" ]] && { log_error "No image specified"; export API_IMAGE=""; return; }
      export API_IMAGE="$hub_image"
      ;;
    3)
      export API_IMAGE=""
      log_warn "Skipping API image"
      ;;
    *)
      log_error "Invalid option"
      exit 1
      ;;
  esac
}

handle_dashboard_image() {
  print_header "Banking Dashboard Image"
  echo "1) Build and push to Docker Hub"
  echo "2) Use existing image from Docker Hub"
  echo "3) Skip"
  read -p "Choose option [1-3]: " -n 1 -r
  echo

  case $REPLY in
    1)
      read -p "Enter your Docker Hub username: " dh_user
      local image="$dh_user/banking-dashboard:v1.0"
      log_info "Building $image..."
      docker build -t "$image" "$APP_DIR/banking-dashboard"
      log_info "Pushing $image..."
      docker push "$image"
      export DASHBOARD_IMAGE="$image"
      ;;
    2)
      read -p "Enter Docker Hub image (e.g., username/banking-dashboard:v1.0): " hub_image
      [[ -z "$hub_image" ]] && { log_error "No image specified"; export DASHBOARD_IMAGE=""; return; }
      export DASHBOARD_IMAGE="$hub_image"
      ;;
    3)
      export DASHBOARD_IMAGE=""
      log_warn "Skipping Dashboard image"
      ;;
    *)
      log_error "Invalid option"
      exit 1
      ;;
  esac
}

update_image_references() {
  if [[ -n "$API_IMAGE" ]]; then
    sed -i "s|image: .*banking-api.*|image: $API_IMAGE|" "$K8S_DIR/04-api-deployment.yaml"
    log_info "Updated API image → $API_IMAGE"
  fi
  if [[ -n "$DASHBOARD_IMAGE" ]] && [[ -s "$K8S_DIR/05-dashboard-deployment.yaml" ]]; then
    sed -i "s|image: .*banking-dashboard.*|image: $DASHBOARD_IMAGE|" "$K8S_DIR/05-dashboard-deployment.yaml"
    log_info "Updated Dashboard image → $DASHBOARD_IMAGE"
  fi
}

# ── /etc/hosts ─────────────────────────────────────────────
setup_hosts() {
  print_header "Configuring /etc/hosts"
  local minikube_ip
  minikube_ip=$(minikube ip)

  if grep -q "banking.local" /etc/hosts; then
    log_warn "banking.local already exists in /etc/hosts"
    # Update IP in case it changed
    sudo sed -i "s/.*banking.local/$minikube_ip banking.local/" /etc/hosts
    log_info "Updated banking.local → $minikube_ip"
  else
    echo "$minikube_ip banking.local" | sudo tee -a /etc/hosts > /dev/null
    log_info "Added banking.local → $minikube_ip to /etc/hosts"
  fi
}

# ── Wait for PostgreSQL ────────────────────────────────────
wait_for_postgres() {
  print_header "Waiting for PostgreSQL"
  log_info "Waiting for postgres-db-0 to be ready..."
  kubectl wait --for=condition=Ready pod/postgres-db-0 \
    -n banking --timeout=300s
  log_info "Waiting for postgres-db-1 to be ready..."
  kubectl wait --for=condition=Ready pod/postgres-db-1 \
    -n banking --timeout=300s
  log_info "PostgreSQL is ready"
}

# ── Deploy ─────────────────────────────────────────────────
deploy_k8s_manifests() {
  print_header "Deploying Kubernetes Manifests"

  # Step 1 — Namespace first
  log_info "Applying 00-namespace.yaml..."
  kubectl apply -f "$K8S_DIR/00-namespace.yaml"

  # Step 2 — ConfigMap for postgres init script
  log_info "Creating postgres-init-script ConfigMap..."
  kubectl create configmap postgres-init-script \
    --from-file=init.sh="$K8S_DIR/scripts/postgres-init.sh" \
    --namespace=banking \
    --dry-run=client -o yaml | kubectl apply -f -

  # Step 3 — Remaining manifests in dependency order
  local manifest_order=(
    "01-configmap.yaml"
    "02-secret.yaml"
    "06-services.yaml"              # headless service before StatefulSet
    "03-postgres-statefulset.yaml"
    "04-api-deployment.yaml"
    "05-dashboard-deployment.yaml"
    "07-ingress.yaml"
    "08-hpa-vpa.yaml"
    "09-rbac.yaml"
    "10-networkpolicy.yaml"
    "11-daemonset-fluentd.yaml"
  )

  for manifest in "${manifest_order[@]}"; do
    local manifest_path="$K8S_DIR/$manifest"

    if [[ ! -f "$manifest_path" ]]; then
      log_warn "Not found: $manifest — skipping"
      continue
    fi

    if is_file_empty "$manifest_path"; then
      log_warn "Empty: $manifest — skipping"
      continue
    fi

    log_info "Applying $manifest..."
    kubectl apply -f "$manifest_path"
  done
}

# ── Wait for Deployments ───────────────────────────────────
wait_for_deployments() {
  print_header "Waiting for Deployments"

  log_info "Waiting for PostgreSQL StatefulSet..."
  kubectl rollout status statefulset/postgres-db \
    -n banking --timeout=300s || log_warn "PostgreSQL rollout timeout"

  wait_for_postgres

  if [[ -n "$API_IMAGE" ]]; then
    log_info "Waiting for Banking API..."
    kubectl rollout status deployment/banking-api \
      -n banking --timeout=180s || log_warn "API rollout timeout"
  fi

  if [[ -n "$DASHBOARD_IMAGE" ]]; then
    log_info "Waiting for Dashboard..."
    kubectl rollout status deployment/banking-dashboard \
      -n banking --timeout=180s || log_warn "Dashboard rollout timeout"
  fi

  log_info "All deployments processed"
}

# ── Status ─────────────────────────────────────────────────
show_status() {
  print_header "Deployment Status"

  echo -e "${GREEN}=== Pods ===${NC}"
  kubectl get pods -n banking -o wide
  echo ""

  echo -e "${GREEN}=== Services ===${NC}"
  kubectl get svc -n banking
  echo ""

  echo -e "${GREEN}=== Ingress ===${NC}"
  kubectl get ingress -n banking
  echo ""

  echo -e "${GREEN}=== PVCs ===${NC}"
  kubectl get pvc -n banking
  echo ""

  echo -e "${GREEN}=== Nodes ===${NC}"
  kubectl get nodes -o wide
}

# ── Access Info ────────────────────────────────────────────
show_access_info() {
  print_header "Access Information"
  local minikube_ip
  minikube_ip=$(minikube ip)

  echo "Dashboard:  http://banking.local"
  echo "API:        http://banking.local/api/accounts"
  echo "API health: http://banking.local/api/health"
  echo ""
  echo "Or use port-forward:"
  echo "  kubectl port-forward svc/banking-api-service 3000:3000 -n banking"
  echo "  kubectl port-forward svc/banking-dashboard-service 8080:80 -n banking"
  echo ""
  echo "Verify replication:"
  echo "  kubectl exec -it postgres-db-0 -n banking -- psql -U postgres -c 'SELECT * FROM pg_stat_replication;'"
}

# ── Cleanup ────────────────────────────────────────────────
cleanup() {
  print_header "Cleanup"
  echo "1) Delete banking namespace only"
  echo "2) Stop and delete minikube"
  echo "3) Both"
  echo "4) Cancel"
  read -p "Choose option [1-4]: " -n 1 -r
  echo

  case $REPLY in
    1)
      log_info "Deleting banking namespace..."
      kubectl delete namespace banking --ignore-not-found=true
      log_info "Done"
      ;;
    2)
      log_info "Deleting minikube..."
      minikube delete
      log_info "Done"
      ;;
    3)
      kubectl delete namespace banking --ignore-not-found=true
      minikube delete
      log_info "Done"
      ;;
    *)
      log_info "Cancelled"
      ;;
  esac
}

# ── Main ───────────────────────────────────────────────────
main() {
  print_header "Kubernetes Banking Platform"

  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  full-setup       Fresh minikube install + full deploy"
    echo "  setup            Deploy to existing cluster"
    echo "  configure-nodes  Label and taint nodes only"
    echo "  images           Build and push images only"
    echo "  deploy           Apply manifests only"
    echo "  status           Show deployment status"
    echo "  access           Show access information"
    echo "  cleanup          Remove resources"
    echo ""
    exit 0
  fi

  local command="$1"
  shift

  case "$command" in
    full-setup)
      check_prerequisites
      full_setup
      configure_nodes
      handle_api_image
      handle_dashboard_image
      update_image_references
      deploy_k8s_manifests
      wait_for_deployments
      setup_hosts
      show_status
      show_access_info
      ;;
    setup)
      check_prerequisites
      init_minikube
      configure_nodes
      handle_api_image
      handle_dashboard_image
      update_image_references
      deploy_k8s_manifests
      wait_for_deployments
      setup_hosts
      show_status
      show_access_info
      ;;
    configure-nodes)
      configure_nodes
      ;;
    images)
      handle_api_image
      handle_dashboard_image
      update_image_references
      ;;
    deploy)
      deploy_k8s_manifests
      wait_for_deployments
      show_status
      ;;
    status)
      show_status
      ;;
    access)
      show_access_info
      ;;
    cleanup)
      cleanup
      ;;
    *)
      log_error "Unknown command: $command"
      exit 1
      ;;
  esac
}

main "$@"