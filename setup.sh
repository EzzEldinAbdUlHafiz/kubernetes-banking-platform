#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"
APP_DIR="$SCRIPT_DIR/app"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo ""
    echo "========================================"
    echo " $1"
    echo "========================================"
}

is_file_empty() {
    local file="$1"
    if [[ ! -s "$file" ]]; then
        return 0
    fi
    return 1
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing=()

    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi

    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi

    if ! command -v minikube &> /dev/null; then
        missing+=("minikube")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

init_minikube() {
    print_header "Initializing Minikube"

    if minikube status &> /dev/null; then
        log_warn "Minikube is already running"
        read -p "Do you want to restart minikube? (y/N): " -n 1 -r
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

    log_info "Starting minikube with adequate resources..."
    minikube start --cpus=4 --memory=8g --driver=docker

    log_info "Configuring node taints and labels..."

    local nodes=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))

    for node in "${nodes[@]}"; do
        if kubectl get node "$node" -o jsonpath='{.spec.taints}' | grep -q "control-plane"; then
            log_info "Tainting master node: $node (NoSchedule)"
            kubectl taint nodes "$node" node-role.kubernetes.io/control-plane=:NoSchedule --overwrite 2>/dev/null || true
            kubectl taint nodes "$node" master=:NoSchedule --overwrite 2>/dev/null || true
        fi
    done

    local worker_found=false
    for node in "${nodes[@]}"; do
        if ! kubectl get node "$node" -o jsonpath='{.spec.taints}' | grep -q "control-plane"; then
            log_info "Labeling and tainting worker node: $node"
            kubectl label node "$node" type=high-memory --overwrite
            kubectl taint nodes "$node" database-only=true:NoSchedule --overwrite
            worker_found=true
            break
        fi
    done

    if ! $worker_found; then
        log_warn "No worker node found. Using first available node."
        local first_node="${nodes[0]}"
        kubectl label node "$first_node" type=high-memory --overwrite
        kubectl taint nodes "$first_node" database-only=true:NoSchedule --overwrite
    fi

    log_info "Minikube initialization complete"
}

handle_api_image() {
    print_header "Banking API Image"

    echo "1) Build locally (minikube image build)"
    echo "2) Use existing image from Docker Hub"
    echo "3) Skip (don't deploy API)"
    read -p "Choose option [1-3]: " -n 1 -r
    echo

    case $REPLY in
        1)
            local image_name="banking-api"
            local image_tag="v1.0"
            log_info "Building Docker image: $image_name:$image_tag"
            minikube image build -t "$image_name:$image_tag" -t "$image_name:latest" "$APP_DIR/banking-api"
            log_info "Loading image into cluster..."
            minikube image load "$image_name:$image_tag"
            minikube image load "$image_name:latest"
            export API_IMAGE="$image_name:$image_tag"
            ;;
        2)
            read -p "Enter Docker Hub image (e.g., username/banking-api:v1.0): " hub_image
            if [[ -z "$hub_image" ]]; then
                log_error "No image specified, skipping API"
                export API_IMAGE=""
            else
                export API_IMAGE="$hub_image"
            fi
            ;;
        3)
            export API_IMAGE=""
            log_warn "Skipping API deployment"
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

handle_dashboard_image() {
    print_header "Banking Dashboard Image"

    echo "1) Build locally (minikube image build)"
    echo "2) Use existing image from Docker Hub"
    echo "3) Skip (don't deploy Dashboard)"
    read -p "Choose option [1-3]: " -n 1 -r
    echo

    case $REPLY in
        1)
            local image_name="banking-dashboard"
            local image_tag="v1.0"
            log_info "Building Docker image: $image_name:$image_tag"
            minikube image build -t "$image_name:$image_tag" -t "$image_name:latest" "$APP_DIR/banking-dashboard"
            log_info "Loading image into cluster..."
            minikube image load "$image_name:$image_tag"
            minikube image load "$image_name:latest"
            export DASHBOARD_IMAGE="$image_name:$image_tag"
            ;;
        2)
            read -p "Enter Docker Hub image (e.g., username/banking-dashboard:v1.0): " hub_image
            if [[ -z "$hub_image" ]]; then
                log_error "No image specified, skipping Dashboard"
                export DASHBOARD_IMAGE=""
            else
                export DASHBOARD_IMAGE="$hub_image"
            fi
            ;;
        3)
            export DASHBOARD_IMAGE=""
            log_warn "Skipping Dashboard deployment"
            ;;
        *)
            log_error "Invalid option"
            exit 1
            ;;
    esac
}

update_image_references() {
    if [[ -n "$API_IMAGE" ]]; then
        sed -i "s|image: YOUR_USER/banking-api:v1.0|image: $API_IMAGE|" "$K8S_DIR/04-api-deployment.yaml"
        log_info "Updated API image reference in manifest"
    fi

    if [[ -n "$DASHBOARD_IMAGE" ]] && [[ -s "$K8S_DIR/05-dashboard-deployment.yaml" ]]; then
        sed -i "s|image: YOUR_USER/banking-dashboard:v1.0|image: $DASHBOARD_IMAGE|" "$K8S_DIR/05-dashboard-deployment.yaml"
        log_info "Updated Dashboard image reference in manifest"
    fi
}

deploy_k8s_manifests() {
    print_header "Deploying Kubernetes Manifests"

    local manifest_order=(
        "00-namespace.yaml"
        "01-configmap.yaml"
        "02-secret.yaml"
        "03-postgres-statefulset.yaml"
        "06-services.yaml"
        "04-api-deployment.yaml"
        "05-dashboard-deployment.yaml"
    )

    for manifest in "${manifest_order[@]}"; do
        local manifest_path="$K8S_DIR/$manifest"

        if [[ ! -f "$manifest_path" ]]; then
            log_warn "Manifest not found: $manifest, skipping"
            continue
        fi

        if is_file_empty "$manifest_path"; then
            log_warn "Manifest is empty: $manifest, skipping"
            continue
        fi

        log_info "Applying $manifest..."
        kubectl apply -f "$manifest_path"
    done
}

wait_for_deployments() {
    print_header "Waiting for Deployments"

    log_info "Waiting for PostgreSQL StatefulSet..."
    kubectl rollout status statefulset/postgres-db -n banking --timeout=300s || log_warn "PostgreSQL rollout timeout, continuing..."

    if [[ -n "$API_IMAGE" ]]; then
        log_info "Waiting for Banking API deployment..."
        kubectl rollout deployment/banking-api -n banking --timeout=180s || log_warn "API rollout timeout, continuing..."
    fi

    if [[ -n "$DASHBOARD_IMAGE" ]]; then
        log_info "Waiting for Dashboard deployment..."
        kubectl rollout deployment/banking-dashboard -n banking --timeout=180s || log_warn "Dashboard rollout timeout, continuing..."
    fi

    log_info "All deployments processed"
}

show_status() {
    print_header "Deployment Status"

    echo -e "${GREEN}=== Pods ===${NC}"
    kubectl get pods -n banking

    echo ""
    echo -e "${GREEN}=== Services ===${NC}"
    kubectl get svc -n banking

    echo ""
    echo -e "${GREEN}=== Nodes (with taints/labels) ===${NC}"
    kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name): taints=\(.spec.taints | map(.key) | join(", ")), labels=\(.metadata.labels | to_entries | map("\(.key)=\(.value)") | join(", "))"'
}

show_access_info() {
    print_header "Access Information"

    echo "Run these commands to access services:"
    echo ""
    echo "Banking API:"
    echo "  minikube service banking-api-service -n banking"
    echo ""
    echo "Banking Dashboard:"
    echo "  minikube service banking-dashboard-service -n banking"
    echo ""
    echo "Or use port-forward:"
    echo "  kubectl port-forward -n banking svc/banking-api-service 3000:3000"
    echo "  kubectl port-forward -n banking svc/banking-dashboard-service 80:80"
}

cleanup() {
    print_header "Cleanup"

    echo "1) Delete all banking namespace resources"
    echo "2) Stop and delete minikube"
    echo "3) Both"
    echo "4) Cancel"
    read -p "Choose option [1-4]: " -n 1 -r
    echo

    case $REPLY in
        1)
            log_info "Deleting banking namespace..."
            kubectl delete namespace banking --ignore-not-found=true
            log_info "Cleanup complete"
            ;;
        2)
            log_info "Stopping and deleting minikube..."
            minikube delete
            log_info "Cleanup complete"
            ;;
        3)
            log_info "Deleting banking namespace..."
            kubectl delete namespace banking --ignore-not-found=true
            log_info "Stopping and deleting minikube..."
            minikube delete
            log_info "Cleanup complete"
            ;;
        *)
            log_info "Cleanup cancelled"
            ;;
    esac
}

main() {
    echo ""
    echo "========================================"
    echo " Kubernetes Banking Platform Setup"
    echo "========================================"
    echo ""

    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  setup     - Run full setup (default)"
        echo "  image     - Handle images only"
        echo "  deploy    - Deploy K8s manifests only"
        echo "  status    - Show deployment status"
        echo "  access    - Show access information"
        echo "  cleanup   - Clean up resources"
        echo ""
        exit 0
    fi

    local command="$1"
    shift

    case "$command" in
        setup)
            check_prerequisites
            init_minikube
            handle_api_image
            handle_dashboard_image
            update_image_references
            deploy_k8s_manifests
            wait_for_deployments
            show_status
            show_access_info
            ;;
        image)
            handle_api_image
            handle_dashboard_image
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