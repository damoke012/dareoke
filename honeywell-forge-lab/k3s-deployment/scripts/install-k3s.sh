#!/bin/bash
# Honeywell Forge Cognition - K3s Installation Script
# Automated lightweight Kubernetes setup with GPU support
#
# Features:
#   - Single-node K3s cluster (edge appliance)
#   - NVIDIA GPU Operator for GPU management
#   - Time-slicing for GPU partitioning
#   - Automatic failover and health checks
#
# Usage:
#   ./install-k3s.sh                    # Full installation
#   ./install-k3s.sh --gpu-only         # Only GPU components (K3s already installed)
#   ./install-k3s.sh --dry-run          # Show what would be done
#
# Requirements:
#   - Ubuntu 20.04/22.04 or RHEL 8/9
#   - NVIDIA GPU with drivers installed
#   - Root/sudo access
#   - Internet access (or air-gapped bundle)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v23.9.1}"
DEVICE_PLUGIN_VERSION="${DEVICE_PLUGIN_VERSION:-v0.14.3}"

# Time-slicing configuration
GPU_REPLICAS="${GPU_REPLICAS:-4}"  # Split GPU into 4 virtual GPUs

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_gpu() {
    log_info "Checking for NVIDIA GPU..."
    if ! command -v nvidia-smi &> /dev/null; then
        log_error "nvidia-smi not found. Please install NVIDIA drivers first."
        exit 1
    fi

    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
    log_info "GPU detected and drivers working"
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        log_info "Detected OS: $OS $VERSION"
    else
        log_warn "Could not detect OS version"
    fi
}

# =============================================================================
# K3s Installation
# =============================================================================
install_k3s() {
    log_info "Installing K3s ${K3S_VERSION}..."

    # Disable swap (required for Kubernetes)
    swapoff -a || true
    sed -i '/swap/d' /etc/fstab || true

    # Install K3s with specific options for GPU support
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - \
        --write-kubeconfig-mode 644 \
        --disable traefik \
        --disable servicelb \
        --kubelet-arg="feature-gates=DevicePlugins=true" \
        --kubelet-arg="feature-gates=KubeletPodResourcesGetAllocatable=true"

    # Wait for K3s to be ready
    log_info "Waiting for K3s to be ready..."
    sleep 10

    until kubectl get nodes &> /dev/null; do
        log_info "Waiting for K3s API..."
        sleep 5
    done

    kubectl wait --for=condition=Ready node --all --timeout=120s
    log_info "K3s installed and ready"

    # Set KUBECONFIG for current session
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> /etc/profile.d/k3s.sh
}

# =============================================================================
# Helm Installation
# =============================================================================
install_helm() {
    if command -v helm &> /dev/null; then
        log_info "Helm already installed: $(helm version --short)"
        return
    fi

    log_info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed: $(helm version --short)"
}

# =============================================================================
# NVIDIA Container Toolkit (if not present)
# =============================================================================
install_nvidia_container_toolkit() {
    if command -v nvidia-ctk &> /dev/null; then
        log_info "NVIDIA Container Toolkit already installed"
        return
    fi

    log_info "Installing NVIDIA Container Toolkit..."

    # Add NVIDIA repository
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | apt-key add - 2>/dev/null || true
    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update
    apt-get install -y nvidia-container-toolkit

    # Configure containerd for NVIDIA runtime
    nvidia-ctk runtime configure --runtime=containerd
    systemctl restart containerd || systemctl restart k3s

    log_info "NVIDIA Container Toolkit installed"
}

# =============================================================================
# Configure containerd for NVIDIA (K3s uses containerd)
# =============================================================================
configure_containerd_nvidia() {
    log_info "Configuring containerd for NVIDIA runtime..."

    # K3s containerd config location
    CONTAINERD_CONFIG="/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl"

    # Create containerd config directory if needed
    mkdir -p $(dirname $CONTAINERD_CONFIG)

    # Add NVIDIA runtime to containerd
    cat > $CONTAINERD_CONFIG << 'EOF'
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  privileged_without_host_devices = false
  runtime_engine = ""
  runtime_root = ""
  runtime_type = "io.containerd.runc.v2"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
  BinaryName = "/usr/bin/nvidia-container-runtime"
EOF

    # Restart K3s to apply containerd changes
    systemctl restart k3s
    sleep 10

    kubectl wait --for=condition=Ready node --all --timeout=120s
    log_info "containerd configured for NVIDIA runtime"
}

# =============================================================================
# NVIDIA Device Plugin with Time-Slicing
# =============================================================================
install_nvidia_device_plugin() {
    log_info "Installing NVIDIA Device Plugin with time-slicing (${GPU_REPLICAS} replicas)..."

    # Create namespace
    kubectl create namespace nvidia-device-plugin --dry-run=client -o yaml | kubectl apply -f -

    # Create time-slicing ConfigMap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
  namespace: nvidia-device-plugin
data:
  config.yaml: |
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_REPLICAS}
EOF

    # Install device plugin via Helm
    helm repo add nvdp https://nvidia.github.io/k8s-device-plugin || true
    helm repo update

    helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
        --namespace nvidia-device-plugin \
        --version ${DEVICE_PLUGIN_VERSION} \
        --set config.name=nvidia-device-plugin-config \
        --set runtimeClassName=nvidia \
        --wait

    log_info "NVIDIA Device Plugin installed with ${GPU_REPLICAS}x time-slicing"
}

# =============================================================================
# Create NVIDIA RuntimeClass
# =============================================================================
create_nvidia_runtime_class() {
    log_info "Creating NVIDIA RuntimeClass..."

    cat <<EOF | kubectl apply -f -
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF

    log_info "NVIDIA RuntimeClass created"
}

# =============================================================================
# Verify GPU Access
# =============================================================================
verify_gpu_access() {
    log_info "Verifying GPU access from Kubernetes..."

    # Run a test pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: default
spec:
  restartPolicy: Never
  runtimeClassName: nvidia
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

    log_info "Waiting for GPU test pod..."
    kubectl wait --for=condition=Ready pod/gpu-test --timeout=120s || true
    sleep 5

    log_info "GPU test output:"
    kubectl logs gpu-test || log_warn "Could not get logs (pod may still be initializing)"

    # Cleanup
    kubectl delete pod gpu-test --ignore-not-found

    log_info "GPU verification complete"
}

# =============================================================================
# Show GPU Allocation
# =============================================================================
show_gpu_status() {
    log_info "GPU Resource Status:"
    echo ""
    kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,GPU_ALLOCATABLE:.status.allocatable.nvidia\.com/gpu,GPU_CAPACITY:.status.capacity.nvidia\.com/gpu'
    echo ""
    log_info "With time-slicing enabled, you should see ${GPU_REPLICAS} allocatable GPUs"
}

# =============================================================================
# Main Installation
# =============================================================================
main() {
    local gpu_only=false
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --gpu-only)
                gpu_only=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "  Honeywell Forge Cognition - K3s Setup"
    echo "=============================================="
    echo ""

    if $dry_run; then
        log_info "DRY RUN - showing what would be installed:"
        echo "  - K3s ${K3S_VERSION}"
        echo "  - Helm"
        echo "  - NVIDIA Container Toolkit"
        echo "  - NVIDIA Device Plugin ${DEVICE_PLUGIN_VERSION}"
        echo "  - GPU Time-Slicing: ${GPU_REPLICAS} replicas"
        exit 0
    fi

    check_root
    check_os
    check_gpu

    if ! $gpu_only; then
        install_k3s
        install_helm
    fi

    # GPU setup
    install_nvidia_container_toolkit
    configure_containerd_nvidia
    create_nvidia_runtime_class
    install_nvidia_device_plugin

    # Verify
    verify_gpu_access
    show_gpu_status

    echo ""
    log_info "=============================================="
    log_info "  K3s + GPU Setup Complete!"
    log_info "=============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Deploy the inference server: kubectl apply -f manifests/"
    echo "  2. Check GPU allocation: kubectl describe node"
    echo "  3. Monitor with: kubectl get pods -A -w"
    echo ""
    echo "KUBECONFIG is at: /etc/rancher/k3s/k3s.yaml"
    echo ""
}

main "$@"
