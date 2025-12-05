#!/bin/bash
#
# Forge Cognition Prototype - Health Check Script
# ================================================
#

set -e

NAMESPACE="forge-inference"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "=========================================="
echo "  Forge Cognition Health Check"
echo "=========================================="
echo ""

FAILED=0

# Check namespace exists
echo "Checking namespace..."
if oc get namespace ${NAMESPACE} &>/dev/null; then
    log_pass "Namespace '${NAMESPACE}' exists"
else
    log_fail "Namespace '${NAMESPACE}' not found"
    FAILED=1
fi

# Check Triton deployment
echo "Checking Triton deployment..."
READY_REPLICAS=$(oc get deployment triton-inference-server -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$READY_REPLICAS" -ge 1 ]]; then
    log_pass "Triton deployment ready (${READY_REPLICAS} replicas)"
else
    log_fail "Triton deployment not ready"
    FAILED=1
fi

# Check Triton pod is running
echo "Checking Triton pod..."
POD_STATUS=$(oc get pods -n ${NAMESPACE} -l app=triton -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$POD_STATUS" == "Running" ]]; then
    log_pass "Triton pod is running"
else
    log_fail "Triton pod status: ${POD_STATUS}"
    FAILED=1
fi

# Get Triton pod name
TRITON_POD=$(oc get pod -n ${NAMESPACE} -l app=triton -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [[ -n "$TRITON_POD" ]]; then
    # Check GPU is visible
    echo "Checking GPU visibility..."
    if oc exec -n ${NAMESPACE} ${TRITON_POD} -- nvidia-smi &>/dev/null; then
        log_pass "GPU is visible in container"

        # Get GPU info
        GPU_NAME=$(oc exec -n ${NAMESPACE} ${TRITON_POD} -- nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        GPU_MEM=$(oc exec -n ${NAMESPACE} ${TRITON_POD} -- nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1)
        echo "        GPU: ${GPU_NAME} (${GPU_MEM})"
    else
        log_fail "GPU not visible in container"
        FAILED=1
    fi

    # Check Triton health endpoint
    echo "Checking Triton HTTP health..."
    if oc exec -n ${NAMESPACE} ${TRITON_POD} -- curl -sf localhost:8000/v2/health/ready &>/dev/null; then
        log_pass "Triton HTTP endpoint is healthy"
    else
        log_warn "Triton HTTP endpoint not ready (may be loading models)"
    fi

    # Check Triton metrics endpoint
    echo "Checking Triton metrics..."
    if oc exec -n ${NAMESPACE} ${TRITON_POD} -- curl -sf localhost:8002/metrics &>/dev/null; then
        log_pass "Triton metrics endpoint is accessible"
    else
        log_warn "Triton metrics endpoint not accessible"
    fi

    # Check model repository
    echo "Checking model repository..."
    MODEL_COUNT=$(oc exec -n ${NAMESPACE} ${TRITON_POD} -- ls /models 2>/dev/null | wc -l || echo "0")
    if [[ "$MODEL_COUNT" -gt 0 ]]; then
        log_pass "Model repository has ${MODEL_COUNT} items"
        oc exec -n ${NAMESPACE} ${TRITON_POD} -- ls -la /models 2>/dev/null | head -10
    else
        log_warn "Model repository is empty (run model build job)"
    fi

    # Check loaded models
    echo "Checking loaded models..."
    MODELS=$(oc exec -n ${NAMESPACE} ${TRITON_POD} -- curl -sf localhost:8000/v2/models 2>/dev/null || echo "{}")
    MODEL_LIST=$(echo "$MODELS" | jq -r '.models[].name' 2>/dev/null || echo "")
    if [[ -n "$MODEL_LIST" ]]; then
        log_pass "Loaded models:"
        for model in $MODEL_LIST; do
            echo "        - ${model}"
        done
    else
        log_warn "No models loaded yet"
    fi
fi

# Check PVC
echo "Checking PVC..."
PVC_STATUS=$(oc get pvc model-repository -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [[ "$PVC_STATUS" == "Bound" ]]; then
    log_pass "Model repository PVC is bound"
else
    log_fail "Model repository PVC status: ${PVC_STATUS}"
    FAILED=1
fi

# Summary
echo ""
echo "=========================================="
if [[ "$FAILED" -eq 0 ]]; then
    echo -e "  ${GREEN}All health checks passed!${NC}"
else
    echo -e "  ${RED}Some health checks failed.${NC}"
fi
echo "=========================================="
echo ""

exit $FAILED
