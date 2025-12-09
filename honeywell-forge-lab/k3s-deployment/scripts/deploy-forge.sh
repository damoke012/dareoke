#!/bin/bash
# Honeywell Forge Cognition - Deploy to K3s
# Deploys all manifests in correct order

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check kubectl access
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    log_info "Make sure K3s is running and KUBECONFIG is set"
    exit 1
fi

echo "=============================================="
echo "  Deploying Forge Cognition to K3s"
echo "=============================================="
echo ""

# Deploy in order
log_info "Creating namespace..."
kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"

log_info "Creating priority classes..."
kubectl apply -f "${MANIFEST_DIR}/priority-class.yaml"

log_info "Creating resource quotas..."
kubectl apply -f "${MANIFEST_DIR}/resource-quota.yaml"

log_info "Creating storage..."
kubectl apply -f "${MANIFEST_DIR}/storage.yaml"

log_info "Creating ConfigMaps..."
kubectl apply -f "${MANIFEST_DIR}/inference-configmap.yaml"

log_info "Creating network policies..."
kubectl apply -f "${MANIFEST_DIR}/network-policy.yaml" || log_warn "Network policies may require CNI support"

log_info "Deploying inference server..."
kubectl apply -f "${MANIFEST_DIR}/inference-deployment.yaml"

log_info "Creating PDB..."
kubectl apply -f "${MANIFEST_DIR}/pod-disruption-budget.yaml"

log_info "Creating HPA..."
kubectl apply -f "${MANIFEST_DIR}/hpa-gpu.yaml" || log_warn "HPA may require metrics-server"

# Wait for deployment
log_info "Waiting for inference server to be ready..."
kubectl rollout status deployment/inference-server -n forge-cognition --timeout=600s || {
    log_warn "Deployment not ready within timeout"
    log_info "Check status with: kubectl get pods -n forge-cognition"
}

echo ""
log_info "=============================================="
log_info "  Deployment Complete!"
log_info "=============================================="
echo ""

# Show status
kubectl get pods -n forge-cognition
echo ""

# Get NodePort
NODEPORT=$(kubectl get svc inference-server-external -n forge-cognition -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30080")
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "Access inference server at:"
echo "  Internal: http://inference-server.forge-cognition:8000"
echo "  External: http://${NODE_IP}:${NODEPORT}"
echo ""
echo "Test with:"
echo "  curl http://${NODE_IP}:${NODEPORT}/health"
