#!/bin/bash
# =============================================================================
# Deploy K3s GPU Cluster - Complete Automated Deployment
# =============================================================================
#
# This is the master orchestration script that deploys a complete K3s cluster
# with GPU support. It handles all dependencies in the correct order:
#
#   1. [Optional] Provision VMs (if using ESXi)
#   2. Setup GPU node prerequisites
#   3. Install K3s cluster
#   4. Sync GPU images to registry (if airgapped)
#   5. Install GPU Operator with time-slicing
#
# Usage:
#   # Full deployment with all defaults
#   K3S_SERVER_IP=x.x.x.x K3S_AGENT_IP=x.x.x.x VM_PASSWORD=xxx ./deploy-gpu-cluster.sh
#
#   # With private registry (airgapped)
#   K3S_SERVER_IP=x.x.x.x K3S_AGENT_IP=x.x.x.x VM_PASSWORD=xxx \
#   REGISTRY_URL=harbor.example.com/nvidia ./deploy-gpu-cluster.sh
#
#   # Skip specific steps
#   SKIP_K3S=true ./deploy-gpu-cluster.sh  # Skip K3s install
#   SKIP_GPU_SETUP=true ./deploy-gpu-cluster.sh  # Skip GPU node setup
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Required configuration
K3S_SERVER_IP="${K3S_SERVER_IP:-}"
K3S_AGENT_IP="${K3S_AGENT_IP:-}"
VM_USER="${VM_USER:-dare}"
VM_PASSWORD="${VM_PASSWORD:-}"

# Optional configuration
REGISTRY_URL="${REGISTRY_URL:-}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"
GPU_TIME_SLICES="${GPU_TIME_SLICES:-4}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v25.10.1}"
DRIVER_VERSION="${DRIVER_VERSION:-535.230.02}"
DRIVER_OS="${DRIVER_OS:-ubuntu22.04}"
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"

# Skip flags
SKIP_GPU_SETUP="${SKIP_GPU_SETUP:-false}"
SKIP_K3S="${SKIP_K3S:-false}"
SKIP_IMAGE_SYNC="${SKIP_IMAGE_SYNC:-false}"
SKIP_REBOOT="${SKIP_REBOOT:-false}"

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
log_header() { echo -e "\n${BLUE}========================================${NC}\n${BLUE}  $1${NC}\n${BLUE}========================================${NC}\n"; }

# Remote execution helpers
remote_cmd() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${ip}" "$cmd"
}

remote_sudo() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${ip}" \
        "echo '${VM_PASSWORD}' | sudo -S bash -c '$cmd'" 2>&1 | grep -v "^\[sudo\] password"
}

wait_for_ssh() {
    local ip="$1"
    local timeout=180
    local elapsed=0

    log_info "Waiting for SSH on ${ip}..."
    while [[ $elapsed -lt $timeout ]]; do
        if sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR "${VM_USER}@${ip}" "echo OK" &>/dev/null; then
            log_info "SSH is ready on ${ip}"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Timeout waiting for SSH on ${ip}"
    return 1
}

check_prereqs() {
    log_step "Checking prerequisites..."

    local errors=0

    if [[ -z "${K3S_SERVER_IP}" ]]; then
        log_error "K3S_SERVER_IP is required"
        errors=$((errors + 1))
    fi

    if [[ -z "${VM_PASSWORD}" ]]; then
        log_error "VM_PASSWORD is required"
        errors=$((errors + 1))
    fi

    if ! command -v sshpass &>/dev/null; then
        log_error "sshpass is required"
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        log_error "Missing prerequisites. Usage:"
        echo "  K3S_SERVER_IP=x.x.x.x K3S_AGENT_IP=x.x.x.x VM_PASSWORD=xxx $0"
        exit 1
    fi

    log_info "Prerequisites OK"
}

# Step 1: Setup GPU node prerequisites
step_setup_gpu_node() {
    if [[ "${SKIP_GPU_SETUP}" == "true" ]]; then
        log_info "Skipping GPU node setup (SKIP_GPU_SETUP=true)"
        return 0
    fi

    if [[ -z "${K3S_AGENT_IP}" ]]; then
        log_warn "No K3S_AGENT_IP specified - skipping GPU node setup"
        log_warn "GPU will only work if server node has GPU passthrough"
        return 0
    fi

    log_header "Step 1: Setup GPU Node"

    wait_for_ssh "${K3S_AGENT_IP}"

    # Check if GPU is visible
    log_info "Checking GPU visibility on ${K3S_AGENT_IP}..."
    if ! remote_sudo "${K3S_AGENT_IP}" "lspci | grep -i nvidia" 2>/dev/null; then
        log_warn "No NVIDIA GPU detected on ${K3S_AGENT_IP}"
        log_warn "Ensure GPU passthrough is configured in the hypervisor"
        log_warn "Continuing anyway..."
    fi

    # Install build dependencies
    log_info "Installing build dependencies..."
    remote_sudo "${K3S_AGENT_IP}" "apt-get update && apt-get install -y build-essential linux-headers-\$(uname -r) dkms pciutils 2>/dev/null || yum install -y kernel-devel-\$(uname -r) kernel-headers-\$(uname -r) gcc make dkms pciutils 2>/dev/null || true"

    # Blacklist nouveau
    log_info "Blacklisting nouveau driver..."
    remote_sudo "${K3S_AGENT_IP}" "cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF"

    # Check if nouveau is loaded
    if remote_sudo "${K3S_AGENT_IP}" "lsmod | grep -q nouveau" 2>/dev/null; then
        log_info "Updating initramfs to remove nouveau..."
        remote_sudo "${K3S_AGENT_IP}" "update-initramfs -u 2>/dev/null || dracut --force 2>/dev/null || true"

        if [[ "${SKIP_REBOOT}" != "true" ]]; then
            log_warn "Nouveau driver is loaded - reboot required"
            log_info "Rebooting ${K3S_AGENT_IP}..."
            remote_sudo "${K3S_AGENT_IP}" "reboot" || true
            sleep 30
            wait_for_ssh "${K3S_AGENT_IP}"
        else
            log_warn "Skipping reboot (SKIP_REBOOT=true) - nouveau may still be loaded"
        fi
    else
        log_info "Nouveau not loaded - no reboot needed"
    fi

    # Setup registries config if using private registry
    if [[ -n "${REGISTRY_URL}" ]]; then
        log_info "Creating K3s registries config..."
        remote_sudo "${K3S_AGENT_IP}" "mkdir -p /etc/rancher/k3s"
        remote_sudo "${K3S_AGENT_IP}" "cat > /etc/rancher/k3s/registries.yaml << 'EOF'
mirrors:
  \"nvcr.io\":
    endpoint:
      - \"https://${REGISTRY_URL%%/*}\"
  \"registry.k8s.io\":
    endpoint:
      - \"https://${REGISTRY_URL%%/*}\"
configs:
  \"${REGISTRY_URL%%/*}\":
    tls:
      insecure_skip_verify: true
EOF"
    fi

    log_info "GPU node setup complete"
}

# Step 2: Install K3s cluster
step_install_k3s() {
    if [[ "${SKIP_K3S}" == "true" ]]; then
        log_info "Skipping K3s installation (SKIP_K3S=true)"
        return 0
    fi

    log_header "Step 2: Install K3s Cluster"

    export K3S_SERVER_IP
    export K3S_AGENT_IP
    export VM_USER
    export VM_PASSWORD
    export K3S_VERSION
    export SERVER_HOSTNAME="${SERVER_HOSTNAME:-k3s-server}"
    export AGENT_HOSTNAME="${AGENT_HOSTNAME:-k3s-gpu-agent}"

    if [[ -f "${SCRIPT_DIR}/install-k3s.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/install-k3s.sh"
        "${SCRIPT_DIR}/install-k3s.sh"
    else
        log_error "install-k3s.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

# Step 3: Sync GPU images to registry (if airgapped)
step_sync_images() {
    if [[ "${SKIP_IMAGE_SYNC}" == "true" ]]; then
        log_info "Skipping image sync (SKIP_IMAGE_SYNC=true)"
        return 0
    fi

    if [[ -z "${REGISTRY_URL}" ]]; then
        log_info "No REGISTRY_URL specified - GPU Operator will pull from internet"
        return 0
    fi

    log_header "Step 3: Sync GPU Images to Registry"

    export REGISTRY_URL
    export REGISTRY_USER
    export REGISTRY_PASSWORD
    export GPU_OPERATOR_VERSION
    export DRIVER_VERSION
    export DRIVER_OS

    if [[ -f "${SCRIPT_DIR}/sync-gpu-images.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/sync-gpu-images.sh"
        "${SCRIPT_DIR}/sync-gpu-images.sh" --push
    else
        log_warn "sync-gpu-images.sh not found - skipping image sync"
    fi
}

# Step 4: Install GPU Operator
step_install_gpu_operator() {
    log_header "Step 4: Install GPU Operator"

    export K3S_SERVER_IP
    export VM_USER
    export VM_PASSWORD
    export GPU_TIME_SLICES
    export GPU_OPERATOR_VERSION
    export DRIVER_VERSION
    export DRIVER_OS
    export REGISTRY_URL

    if [[ -f "${SCRIPT_DIR}/install-gpu-operator.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/install-gpu-operator.sh"
        "${SCRIPT_DIR}/install-gpu-operator.sh"
    else
        log_error "install-gpu-operator.sh not found in ${SCRIPT_DIR}"
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    log_header "Verifying Deployment"

    log_info "Checking K3s nodes..."
    remote_sudo "${K3S_SERVER_IP}" "kubectl get nodes -o wide"

    log_info "Checking GPU Operator pods..."
    remote_sudo "${K3S_SERVER_IP}" "kubectl get pods -n gpu-operator"

    log_info "Checking GPU resources..."
    remote_sudo "${K3S_SERVER_IP}" "kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu'"
}

# Main deployment
deploy() {
    echo ""
    log_header "K3s GPU Cluster Deployment"
    echo ""
    log_info "K3s Server:       ${K3S_SERVER_IP}"
    log_info "K3s Agent:        ${K3S_AGENT_IP:-none (single node)}"
    log_info "K3s Version:      ${K3S_VERSION}"
    log_info "GPU Operator:     ${GPU_OPERATOR_VERSION}"
    log_info "Driver:           ${DRIVER_VERSION}-${DRIVER_OS}"
    log_info "GPU Time Slices:  ${GPU_TIME_SLICES}"
    log_info "Registry:         ${REGISTRY_URL:-none (online)}"
    echo ""

    check_prereqs

    step_setup_gpu_node
    step_install_k3s
    step_sync_images
    step_install_gpu_operator

    verify_deployment

    echo ""
    log_header "Deployment Complete!"
    echo ""
    log_info "K3s cluster with GPU support is ready!"
    log_info "GPU time slices: ${GPU_TIME_SLICES}"
    echo ""
    echo "Access the cluster:"
    echo "  ssh ${VM_USER}@${K3S_SERVER_IP}"
    echo "  sudo kubectl get nodes"
    echo ""
    echo "Test GPU access:"
    echo "  sudo kubectl run gpu-test --rm -it --restart=Never \\"
    echo "    --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \\"
    echo "    --limits=nvidia.com/gpu=1 -- nvidia-smi"
    echo ""
}

show_help() {
    cat << EOF
K3s GPU Cluster Deployment Script

This script deploys a complete K3s cluster with GPU support including:
  1. GPU node prerequisites setup
  2. K3s cluster installation
  3. GPU image sync to private registry (optional)
  4. GPU Operator installation with time-slicing

Usage:
  $0 [OPTIONS]

Required Environment Variables:
  K3S_SERVER_IP        K3s server node IP
  VM_PASSWORD          SSH password for VMs

Optional Environment Variables:
  K3S_AGENT_IP         K3s GPU agent node IP (for multi-node)
  VM_USER              SSH username (default: dare)
  K3S_VERSION          K3s version (default: v1.28.4+k3s1)
  GPU_OPERATOR_VERSION GPU Operator version (default: v25.10.1)
  DRIVER_VERSION       NVIDIA driver version (default: 535.230.02)
  DRIVER_OS            Driver OS tag (default: ubuntu22.04)
  GPU_TIME_SLICES      Number of GPU time slices (default: 4)
  REGISTRY_URL         Private registry URL for airgapped deployment
  REGISTRY_USER        Registry username
  REGISTRY_PASSWORD    Registry password

Skip Flags:
  SKIP_GPU_SETUP=true  Skip GPU node setup
  SKIP_K3S=true        Skip K3s installation
  SKIP_IMAGE_SYNC=true Skip image sync to registry
  SKIP_REBOOT=true     Skip node reboot (not recommended)

Options:
  --verify    Verify existing deployment
  --help, -h  Show this help

Examples:
  # Online deployment (internet access)
  K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 \\
  VM_PASSWORD=secret $0

  # Airgapped deployment with Harbor
  K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 \\
  VM_PASSWORD=secret \\
  REGISTRY_URL=harbor.example.com/nvidia \\
  REGISTRY_USER=admin REGISTRY_PASSWORD=secret $0

  # Skip K3s install (already installed)
  K3S_SERVER_IP=192.168.1.100 VM_PASSWORD=secret \\
  SKIP_K3S=true $0

  # Verify deployment
  K3S_SERVER_IP=192.168.1.100 VM_PASSWORD=secret $0 --verify
EOF
}

# Main
case "${1:-}" in
    --verify)
        check_prereqs
        verify_deployment
        ;;
    --help|-h)
        show_help
        ;;
    *)
        deploy
        ;;
esac
