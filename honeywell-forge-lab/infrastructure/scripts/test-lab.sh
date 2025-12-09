#!/bin/bash
# Honeywell Forge Cognition - Lab Validation Script
# Run this after deployment to verify everything works
#
# Usage:
#   ./test-lab.sh <LAB_IP>
#   ./test-lab.sh 192.168.1.100
#

set -euo pipefail

LAB_IP="${1:-}"

if [[ -z "$LAB_IP" ]]; then
    echo "Usage: $0 <LAB_IP>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "      $1"; }

FAILURES=0
NODEPORT=30080

echo "=============================================="
echo "  Lab Validation Tests"
echo "=============================================="
echo "  Target: $LAB_IP"
echo "=============================================="
echo ""

# =============================================================================
# Test 1: SSH Connectivity
# =============================================================================
echo "[Test 1] SSH Connectivity"
if ssh -o ConnectTimeout=5 -o BatchMode=yes root@$LAB_IP "echo ok" &>/dev/null; then
    pass "SSH connection successful"
else
    fail "Cannot SSH to $LAB_IP"
    echo "Fix: ssh-copy-id root@$LAB_IP"
    exit 1
fi

# =============================================================================
# Test 2: NVIDIA Driver
# =============================================================================
echo ""
echo "[Test 2] NVIDIA Driver"
GPU_INFO=$(ssh root@$LAB_IP "nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader" 2>/dev/null || echo "")
if [[ -n "$GPU_INFO" ]]; then
    pass "NVIDIA driver working"
    info "GPU: $GPU_INFO"
else
    fail "NVIDIA driver not working"
fi

# =============================================================================
# Test 3: K3s Running
# =============================================================================
echo ""
echo "[Test 3] K3s Status"
K3S_STATUS=$(ssh root@$LAB_IP "systemctl is-active k3s" 2>/dev/null || echo "inactive")
if [[ "$K3S_STATUS" == "active" ]]; then
    pass "K3s is running"
else
    fail "K3s is not running (status: $K3S_STATUS)"
fi

# =============================================================================
# Test 4: Kubernetes Nodes
# =============================================================================
echo ""
echo "[Test 4] Kubernetes Nodes"
NODES=$(ssh root@$LAB_IP "kubectl get nodes -o wide 2>/dev/null" || echo "")
if [[ -n "$NODES" ]] && echo "$NODES" | grep -q "Ready"; then
    pass "Kubernetes nodes ready"
    info "$(echo "$NODES" | head -2)"
else
    fail "No ready Kubernetes nodes"
fi

# =============================================================================
# Test 5: GPU Allocation (Time-Slicing)
# =============================================================================
echo ""
echo "[Test 5] GPU Time-Slicing"
GPU_ALLOC=$(ssh root@$LAB_IP "kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu' --no-headers" 2>/dev/null || echo "")
if echo "$GPU_ALLOC" | grep -qE "[0-9]+"; then
    GPU_COUNT=$(echo "$GPU_ALLOC" | awk '{print $2}')
    if [[ "$GPU_COUNT" -gt 1 ]]; then
        pass "GPU time-slicing enabled ($GPU_COUNT virtual GPUs)"
    else
        warn "Only $GPU_COUNT GPU(s) - time-slicing may not be configured"
    fi
else
    fail "Cannot get GPU allocation"
fi

# =============================================================================
# Test 6: NVIDIA Device Plugin
# =============================================================================
echo ""
echo "[Test 6] NVIDIA Device Plugin"
PLUGIN_STATUS=$(ssh root@$LAB_IP "kubectl get pods -n nvidia-device-plugin -o wide 2>/dev/null" || echo "")
if echo "$PLUGIN_STATUS" | grep -q "Running"; then
    pass "NVIDIA device plugin running"
else
    fail "NVIDIA device plugin not running"
    info "$PLUGIN_STATUS"
fi

# =============================================================================
# Test 7: Forge Cognition Namespace
# =============================================================================
echo ""
echo "[Test 7] Forge Cognition Namespace"
NS_EXISTS=$(ssh root@$LAB_IP "kubectl get namespace forge-cognition 2>/dev/null" || echo "")
if [[ -n "$NS_EXISTS" ]]; then
    pass "Forge namespace exists"
else
    warn "Forge namespace not found (may not be deployed yet)"
fi

# =============================================================================
# Test 8: Inference Server Pod
# =============================================================================
echo ""
echo "[Test 8] Inference Server Pod"
POD_STATUS=$(ssh root@$LAB_IP "kubectl get pods -n forge-cognition -l app=inference-server 2>/dev/null" || echo "")
if echo "$POD_STATUS" | grep -q "Running"; then
    pass "Inference server pod running"
elif echo "$POD_STATUS" | grep -q "Pending\|ContainerCreating"; then
    warn "Inference server pod starting..."
    info "$POD_STATUS"
else
    warn "Inference server pod not found or not running"
    info "$POD_STATUS"
fi

# =============================================================================
# Test 9: Inference Server Health (via NodePort)
# =============================================================================
echo ""
echo "[Test 9] Inference Server Health Endpoint"
HEALTH=$(curl -s --connect-timeout 5 "http://${LAB_IP}:${NODEPORT}/health" 2>/dev/null || echo "")
if [[ -n "$HEALTH" ]] && echo "$HEALTH" | grep -qiE "healthy|ok|true"; then
    pass "Health endpoint responding"
    info "Response: $HEALTH"
elif [[ -n "$HEALTH" ]]; then
    warn "Health endpoint returned: $HEALTH"
else
    warn "Health endpoint not reachable (pod may still be starting)"
fi

# =============================================================================
# Test 10: GPU Test Pod
# =============================================================================
echo ""
echo "[Test 10] GPU Access Test"
echo "Running GPU test pod..."
GPU_TEST=$(ssh root@$LAB_IP "
kubectl delete pod gpu-test --ignore-not-found 2>/dev/null
kubectl run gpu-test --rm -i --restart=Never \
  --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{\"spec\":{\"runtimeClassName\":\"nvidia\",\"containers\":[{\"name\":\"gpu-test\",\"image\":\"nvidia/cuda:12.2.0-base-ubuntu22.04\",\"command\":[\"nvidia-smi\",\"-L\"],\"resources\":{\"limits\":{\"nvidia.com/gpu\":\"1\"}}}]}}' \
  2>/dev/null || echo 'FAILED'
" 2>/dev/null || echo "FAILED")

if echo "$GPU_TEST" | grep -qi "GPU 0"; then
    pass "GPU accessible from pods"
    info "$(echo "$GPU_TEST" | head -1)"
else
    fail "Cannot access GPU from pods"
    info "$GPU_TEST"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=============================================="
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}  All tests passed!${NC}"
else
    echo -e "${RED}  $FAILURES test(s) failed${NC}"
fi
echo "=============================================="
echo ""

if [[ $FAILURES -eq 0 ]]; then
    echo "Your lab is ready! Access the inference server at:"
    echo "  http://${LAB_IP}:${NODEPORT}"
    echo ""
    echo "Test inference:"
    echo "  curl http://${LAB_IP}:${NODEPORT}/v1/chat -X POST \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"prompt\": \"Hello\", \"max_tokens\": 50}'"
fi

exit $FAILURES
