#!/bin/bash
#
# Forge Cognition Prototype - Deployment Script
# ==============================================
# Deploys the complete inference stack to OpenShift
#
# Usage: ./deploy.sh [--build-model] [--skip-gpu-check]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
NAMESPACE="forge-inference"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Parse arguments
BUILD_MODEL=false
SKIP_GPU_CHECK=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build-model)
            BUILD_MODEL=true
            shift
            ;;
        --skip-gpu-check)
            SKIP_GPU_CHECK=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--build-model] [--skip-gpu-check]"
            echo ""
            echo "Options:"
            echo "  --build-model     Run the TensorRT-LLM model build job"
            echo "  --skip-gpu-check  Skip GPU availability check"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo "=========================================="
echo "  Forge Cognition Prototype Deployment"
echo "=========================================="
echo ""

# Check oc is available
if ! command -v oc &> /dev/null; then
    log_error "oc command not found. Please install OpenShift CLI."
    exit 1
fi

# Check cluster connection
log_step "Checking OpenShift cluster connection..."
if ! oc whoami &> /dev/null; then
    log_error "Not logged into OpenShift cluster. Please run 'oc login' first."
    exit 1
fi
log_info "Connected as: $(oc whoami)"

# Check GPU node availability
if [[ "$SKIP_GPU_CHECK" != "true" ]]; then
    log_step "Checking GPU node availability..."
    GPU_NODES=$(oc get nodes -l nvidia.com/gpu.present=true -o name 2>/dev/null | wc -l)
    if [[ "$GPU_NODES" -eq 0 ]]; then
        log_warn "No nodes with label 'nvidia.com/gpu.present=true' found."
        log_warn "Attempting to find GPU nodes..."

        # Try to find nodes with GPU resources
        GPU_RESOURCE_NODES=$(oc get nodes -o json | jq -r '.items[] | select(.status.allocatable["nvidia.com/gpu"] != null) | .metadata.name' 2>/dev/null)

        if [[ -n "$GPU_RESOURCE_NODES" ]]; then
            log_info "Found GPU nodes: $GPU_RESOURCE_NODES"
            log_info "Labeling GPU nodes..."
            for node in $GPU_RESOURCE_NODES; do
                oc label node "$node" nvidia.com/gpu.present=true --overwrite
            done
        else
            log_error "No GPU nodes found. Please ensure:"
            log_error "  1. GPU Operator is installed"
            log_error "  2. GPU is passed through to worker node"
            log_error "  3. Node is labeled: oc label node <node-name> nvidia.com/gpu.present=true"
            exit 1
        fi
    fi
    log_info "GPU nodes available: $GPU_NODES"
fi

# Deploy manifests in order
log_step "Creating namespace..."
oc apply -f "${MANIFESTS_DIR}/01-namespace.yaml"

log_step "Creating PVCs..."
oc apply -f "${MANIFESTS_DIR}/02-pvc.yaml"

# Wait for PVC to be bound
log_info "Waiting for PVC to be bound..."
oc wait --for=jsonpath='{.status.phase}'=Bound pvc/model-repository -n ${NAMESPACE} --timeout=120s || true

# Build model if requested
if [[ "$BUILD_MODEL" == "true" ]]; then
    log_step "Starting TensorRT-LLM model build job..."

    # Delete existing job if it exists
    oc delete job trtllm-model-build -n ${NAMESPACE} --ignore-not-found=true

    # Apply the build job
    oc apply -f "${MANIFESTS_DIR}/04-model-build-job.yaml"

    log_info "Model build job started. This may take 15-30 minutes."
    log_info "Monitor progress with: oc logs -f job/trtllm-model-build -n ${NAMESPACE}"

    # Wait for job to complete
    log_info "Waiting for model build to complete..."
    if oc wait --for=condition=complete job/trtllm-model-build -n ${NAMESPACE} --timeout=1800s; then
        log_info "Model build completed successfully!"
    else
        log_error "Model build failed or timed out. Check logs:"
        log_error "  oc logs job/trtllm-model-build -n ${NAMESPACE}"
        exit 1
    fi
fi

# Deploy Triton
log_step "Deploying Triton Inference Server..."
oc apply -f "${MANIFESTS_DIR}/03-triton-deployment.yaml"

# Wait for deployment
log_info "Waiting for Triton deployment to be ready..."
if oc rollout status deployment/triton-inference-server -n ${NAMESPACE} --timeout=300s; then
    log_info "Triton Inference Server is ready!"
else
    log_warn "Deployment taking longer than expected. Check pod status:"
    oc get pods -n ${NAMESPACE}
fi

# Get route
log_step "Getting service endpoints..."
ROUTE=$(oc get route triton-http -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
SVC_IP=$(oc get svc triton-inference-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIP}')

echo ""
echo "=========================================="
echo "  Deployment Complete!"
echo "=========================================="
echo ""
echo "Service Endpoints:"
echo "  Internal: http://${SVC_IP}:8000"
if [[ -n "$ROUTE" ]]; then
echo "  External: https://${ROUTE}"
fi
echo ""
echo "Useful commands:"
echo "  Check pods:    oc get pods -n ${NAMESPACE}"
echo "  Check logs:    oc logs -f deployment/triton-inference-server -n ${NAMESPACE}"
echo "  Health check:  ./health_check.sh"
echo "  Run benchmark: ./run_benchmark.sh"
echo ""
