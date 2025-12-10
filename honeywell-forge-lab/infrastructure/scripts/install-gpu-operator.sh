#!/bin/bash
# =============================================================================
# Install NVIDIA GPU Operator on K3s (Airgapped/Offline)
# =============================================================================
#
# This script installs the NVIDIA GPU Operator on a K3s cluster.
# Supports both online and offline (airgapped) installation.
#
# The GPU Operator automatically:
#   - Installs NVIDIA drivers (optional, can use pre-installed)
#   - Installs NVIDIA Container Toolkit
#   - Deploys Device Plugin for GPU scheduling
#   - Configures GPU time-slicing
#
# Usage:
#   # From jump host with kubectl access:
#   ./install-gpu-operator.sh
#
#   # With custom time-slicing replicas:
#   GPU_TIME_SLICES=4 ./install-gpu-operator.sh
#
#   # Skip driver install (use pre-installed drivers):
#   SKIP_DRIVER=true ./install-gpu-operator.sh
#
# Environment Variables:
#   K3S_SERVER_IP      - IP of K3s server (to run kubectl commands)
#   VM_USER            - SSH username (default: dare)
#   VM_PASSWORD        - SSH password (required)
#   GPU_TIME_SLICES    - Number of GPU time slices (default: 4)
#   SKIP_DRIVER        - Skip NVIDIA driver install (default: false)
#   GPU_OPERATOR_VERSION - GPU Operator version (default: v23.9.1)
#
# =============================================================================

set -euo pipefail

# Configuration
K3S_SERVER_IP="${K3S_SERVER_IP:-}"
VM_USER="${VM_USER:-dare}"
VM_PASSWORD="${VM_PASSWORD:-}"
GPU_TIME_SLICES="${GPU_TIME_SLICES:-4}"
SKIP_DRIVER="${SKIP_DRIVER:-false}"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v25.10.1}"
DRIVER_VERSION="${DRIVER_VERSION:-535.230.02}"
DRIVER_OS="${DRIVER_OS:-ubuntu22.04}"
HELM_VERSION="${HELM_VERSION:-v3.13.2}"

# Registry settings for airgapped deployment
REGISTRY_URL="${REGISTRY_URL:-}"  # e.g., harbor.apps.lab.ocp.lan/nvidia
USE_PREINSTALLED_DRIVER="${USE_PREINSTALLED_DRIVER:-false}"

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

# Run command on K3s server
k3s_cmd() {
    local cmd="$1"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${K3S_SERVER_IP}" "$cmd"
}

k3s_sudo() {
    local cmd="$1"
    # Use base64 encoding to safely pass password with special characters (like !!)
    local encoded_pass
    encoded_pass=$(echo -n "${VM_PASSWORD}" | base64)
    # Use sed to remove the [sudo] password prompt from anywhere in the output
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${K3S_SERVER_IP}" "echo ${encoded_pass} | base64 -d | sudo -S bash -c '$cmd'" 2>&1 | sed 's/\[sudo\] password for [^:]*: //g'
}

k3s_copy() {
    local src="$1"
    local dst="$2"
    sshpass -p "${VM_PASSWORD}" scp -o StrictHostKeyChecking=no -o LogLevel=ERROR "$src" "${VM_USER}@${K3S_SERVER_IP}:${dst}"
}

check_prereqs() {
    log_info "Checking prerequisites..."

    if [[ -z "${K3S_SERVER_IP}" ]]; then
        log_error "K3S_SERVER_IP is required"
        exit 1
    fi

    if [[ -z "${VM_PASSWORD}" ]]; then
        log_error "VM_PASSWORD is required"
        exit 1
    fi

    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required"
        exit 1
    fi

    # Test connectivity
    if ! k3s_cmd "echo OK" &>/dev/null; then
        log_error "Cannot connect to K3s server at ${K3S_SERVER_IP}"
        exit 1
    fi

    log_info "Prerequisites OK"
}

install_helm() {
    log_step "Installing Helm on K3s server..."

    # Check if Helm is already installed
    if k3s_sudo "helm version" &>/dev/null; then
        log_info "Helm is already installed"
        return 0
    fi

    log_info "Downloading Helm ${HELM_VERSION}..."
    k3s_sudo "curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o /tmp/helm.tar.gz"
    k3s_sudo "tar -xzf /tmp/helm.tar.gz -C /tmp"
    k3s_sudo "mv /tmp/linux-amd64/helm /usr/local/bin/helm"
    k3s_sudo "chmod +x /usr/local/bin/helm"
    k3s_sudo "rm -rf /tmp/helm.tar.gz /tmp/linux-amd64"

    log_info "Helm installed successfully"
}

create_gpu_namespace() {
    log_step "Creating GPU operator namespace..."

    k3s_sudo "kubectl create namespace gpu-operator 2>/dev/null || true"
    log_info "Namespace gpu-operator ready"
}

create_time_slicing_config() {
    log_step "Creating GPU time-slicing configuration (${GPU_TIME_SLICES} slices)..."

    # Create the config file locally first, then copy it with unique name
    local tmp_config="/tmp/time-slicing-config-$$.yaml"
    local remote_config="/tmp/time-slicing-config-$$.yaml"
    cat > "$tmp_config" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  any: |-
    version: v1
    flags:
      migStrategy: none
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: nvidia.com/gpu
            replicas: ${GPU_TIME_SLICES}
EOF

    k3s_copy "$tmp_config" "$remote_config"
    k3s_sudo "kubectl apply -f $remote_config && rm -f $remote_config"
    rm -f "$tmp_config"
    log_info "Time-slicing config created with ${GPU_TIME_SLICES} replicas"
}

add_nvidia_helm_repo() {
    log_step "Adding NVIDIA Helm repository..."

    # Try to add repo on K3s server first (if it has internet access)
    if k3s_sudo "helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null && helm repo update nvidia 2>/dev/null"; then
        log_info "NVIDIA Helm repo added on K3s server"
        USE_LOCAL_CHART="false"
    else
        log_warn "K3s server has no internet access - will use local chart download"
        USE_LOCAL_CHART="true"

        # Download chart locally on jump host (which has internet)
        log_info "Downloading GPU Operator chart locally..."
        local chart_dir="/tmp/gpu-operator-chart"
        rm -rf "$chart_dir"
        mkdir -p "$chart_dir"

        # Check if helm is available locally
        if ! command -v helm &>/dev/null; then
            log_info "Installing Helm locally..."
            curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        fi

        helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
        helm repo update nvidia
        helm pull nvidia/gpu-operator --version "${GPU_OPERATOR_VERSION#v}" --untar --untardir "$chart_dir"

        # Copy chart to K3s server
        log_info "Copying chart to K3s server..."
        k3s_sudo "rm -rf /tmp/gpu-operator-chart"
        sshpass -p "${VM_PASSWORD}" scp -o StrictHostKeyChecking=no -o LogLevel=ERROR -r "$chart_dir" "${VM_USER}@${K3S_SERVER_IP}:/tmp/"

        log_info "Chart downloaded and copied to K3s server"
    fi
}

install_gpu_operator() {
    log_step "Installing NVIDIA GPU Operator ${GPU_OPERATOR_VERSION}..."

    local helm_args="--namespace gpu-operator --create-namespace"
    helm_args+=" --set devicePlugin.config.name=time-slicing-config"
    helm_args+=" --set devicePlugin.config.default=any"

    # Determine registry (airgapped vs online)
    local registry="nvcr.io/nvidia"
    if [[ -n "${REGISTRY_URL}" ]]; then
        registry="${REGISTRY_URL}"
        log_info "Using private registry: ${registry}"
    fi

    # Driver configuration
    if [[ "${SKIP_DRIVER}" == "true" ]] || [[ "${USE_PREINSTALLED_DRIVER}" == "true" ]]; then
        log_info "Skipping NVIDIA driver installation (using pre-installed drivers)"
        helm_args+=" --set driver.enabled=false"
    else
        # GPU Operator will install driver via container
        log_info "GPU Operator will install driver: ${DRIVER_VERSION}-${DRIVER_OS}"
        helm_args+=" --set driver.enabled=true"
        helm_args+=" --set driver.repository=${registry}"
        helm_args+=" --set driver.version=${DRIVER_VERSION}-${DRIVER_OS}"
    fi

    # Configure all component repositories for airgapped
    if [[ -n "${REGISTRY_URL}" ]]; then
        helm_args+=" --set operator.repository=${registry}"
        helm_args+=" --set toolkit.repository=${registry}"
        helm_args+=" --set devicePlugin.repository=${registry}"
        helm_args+=" --set dcgm.repository=${registry}"
        helm_args+=" --set dcgmExporter.repository=${registry}"
        helm_args+=" --set gfd.repository=${registry}"
        helm_args+=" --set driver.manager.repository=${registry}"
        helm_args+=" --set validator.repository=${registry}"
    fi

    # K3s specific settings
    helm_args+=" --set toolkit.env[0].name=CONTAINERD_CONFIG"
    helm_args+=" --set toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml"
    helm_args+=" --set toolkit.env[1].name=CONTAINERD_SOCKET"
    helm_args+=" --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock"
    helm_args+=" --set toolkit.env[2].name=CONTAINERD_RUNTIME_CLASS"
    helm_args+=" --set toolkit.env[2].value=nvidia"
    helm_args+=" --set toolkit.env[3].name=CONTAINERD_SET_AS_DEFAULT"
    helm_args+=" --set-string toolkit.env[3].value=true"

    # Determine chart source
    local chart_ref="nvidia/gpu-operator"
    if [[ "${USE_LOCAL_CHART:-false}" == "true" ]]; then
        chart_ref="/tmp/gpu-operator-chart/gpu-operator"
        log_info "Using local chart: ${chart_ref}"
    fi

    log_info "Running: helm install gpu-operator ${chart_ref} ${helm_args}"

    # Need to set KUBECONFIG for helm to find the K3s cluster
    k3s_sudo "KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install gpu-operator ${chart_ref} ${helm_args} --wait --timeout 10m" || {
        log_warn "Helm install had issues, checking status..."
    }

    log_info "GPU Operator installation initiated"
}

wait_for_gpu_operator() {
    log_step "Waiting for GPU Operator pods to be ready..."

    local retries=60
    for ((i=1; i<=retries; i++)); do
        # Get counts and trim whitespace/newlines
        local ready=$(k3s_sudo "kubectl get pods -n gpu-operator --no-headers 2>/dev/null | grep -c 'Running' || echo 0" | tr -d '[:space:]')
        local total=$(k3s_sudo "kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l" | tr -d '[:space:]')

        # Default to 0 if empty
        ready=${ready:-0}
        total=${total:-0}

        log_info "GPU Operator pods: ${ready}/${total} Running (attempt ${i}/${retries})"

        if [[ "$ready" -ge 5 ]] && [[ "$ready" == "$total" ]]; then
            log_info "All GPU Operator pods are running!"
            return 0
        fi

        sleep 10
    done

    log_warn "Timeout waiting for GPU Operator pods. Current status:"
    k3s_sudo "kubectl get pods -n gpu-operator"
    return 0
}

verify_gpu_available() {
    log_step "Verifying GPU is available in Kubernetes..."

    local retries=30
    for ((i=1; i<=retries; i++)); do
        local gpu_count=$(k3s_sudo "kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\\.com/gpu}' 2>/dev/null" || echo "0")

        if [[ -n "$gpu_count" && "$gpu_count" != "0" ]]; then
            log_info "GPU resources available: ${gpu_count}"
            return 0
        fi

        log_info "Waiting for GPU to be allocatable... (attempt ${i}/${retries})"
        sleep 10
    done

    log_warn "GPU not yet showing as allocatable. This may take a few more minutes."
    return 0
}

test_gpu_workload() {
    log_step "Testing GPU workload..."

    local test_pod=$(cat <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
)

    echo "$test_pod" | k3s_sudo "cat > /tmp/gpu-test-pod.yaml"

    # Delete existing test pod if exists
    k3s_sudo "kubectl delete pod gpu-test --ignore-not-found=true 2>/dev/null || true"
    sleep 5

    # Create test pod
    k3s_sudo "kubectl apply -f /tmp/gpu-test-pod.yaml"

    # Wait for pod to complete
    log_info "Waiting for GPU test pod to complete..."
    local retries=30
    for ((i=1; i<=retries; i++)); do
        local status=$(k3s_sudo "kubectl get pod gpu-test -o jsonpath='{.status.phase}' 2>/dev/null" || echo "Unknown")

        if [[ "$status" == "Succeeded" ]]; then
            log_info "GPU test passed! nvidia-smi output:"
            k3s_sudo "kubectl logs gpu-test"
            k3s_sudo "kubectl delete pod gpu-test"
            return 0
        elif [[ "$status" == "Failed" ]]; then
            log_error "GPU test failed. Pod logs:"
            k3s_sudo "kubectl logs gpu-test"
            k3s_sudo "kubectl delete pod gpu-test"
            return 1
        fi

        sleep 5
    done

    log_warn "GPU test pod did not complete in time. Status:"
    k3s_sudo "kubectl describe pod gpu-test"
    return 0
}

show_summary() {
    echo ""
    log_step "=============================================="
    log_step "  GPU Operator Installation Complete!"
    log_step "=============================================="
    echo ""
    echo "GPU Time Slices: ${GPU_TIME_SLICES}"
    echo "Operator Version: ${GPU_OPERATOR_VERSION}"
    echo ""
    echo "Verify GPU resources:"
    echo "  kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu'"
    echo ""
    echo "Check GPU Operator pods:"
    echo "  kubectl get pods -n gpu-operator"
    echo ""
    echo "Test GPU access:"
    echo "  kubectl run gpu-test --rm -it --restart=Never \\"
    echo "    --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \\"
    echo "    --limits=nvidia.com/gpu=1 -- nvidia-smi"
    echo ""
}

uninstall_gpu_operator() {
    log_step "Uninstalling GPU Operator..."

    k3s_sudo "helm uninstall gpu-operator -n gpu-operator 2>/dev/null || true"
    k3s_sudo "kubectl delete namespace gpu-operator 2>/dev/null || true"

    log_info "GPU Operator uninstalled"
}

# Main
main() {
    echo ""
    log_step "=============================================="
    log_step "  NVIDIA GPU Operator Installation"
    log_step "=============================================="
    echo ""
    log_info "K3s Server:      ${K3S_SERVER_IP}"
    log_info "GPU Time Slices: ${GPU_TIME_SLICES}"
    log_info "Skip Driver:     ${SKIP_DRIVER}"
    log_info "Operator Version: ${GPU_OPERATOR_VERSION}"
    log_info "Driver Version:  ${DRIVER_VERSION}-${DRIVER_OS}"
    log_info "Registry:        ${REGISTRY_URL:-nvcr.io/nvidia (online)}"
    echo ""

    check_prereqs
    install_helm
    create_gpu_namespace
    create_time_slicing_config
    add_nvidia_helm_repo
    install_gpu_operator
    wait_for_gpu_operator
    verify_gpu_available
    # test_gpu_workload  # Uncomment to run GPU test
    show_summary
}

case "${1:-}" in
    --uninstall)
        check_prereqs
        uninstall_gpu_operator
        ;;
    --test)
        check_prereqs
        test_gpu_workload
        ;;
    --help|-h)
        cat << EOF
NVIDIA GPU Operator Installer for K3s

Usage: $0 [OPTIONS]

Options:
  --uninstall    Uninstall GPU Operator
  --test         Run GPU test workload
  --help, -h     Show this help

Environment Variables:
  K3S_SERVER_IP        K3s server IP (required)
  VM_PASSWORD          SSH password (required)
  VM_USER              SSH user (default: dare)
  GPU_TIME_SLICES      Number of time slices (default: 4)
  SKIP_DRIVER          Skip driver install (default: false)
  GPU_OPERATOR_VERSION Version to install (default: v25.10.1)
  DRIVER_VERSION       NVIDIA driver version (default: 535.230.02)
  DRIVER_OS            Driver OS tag (default: ubuntu22.04)
  REGISTRY_URL         Private registry URL for airgapped (e.g., harbor.apps.lab.ocp.lan/nvidia)

Examples:
  # Basic installation (online)
  K3S_SERVER_IP=192.168.22.91 VM_PASSWORD=secret ./install-gpu-operator.sh

  # Airgapped installation using Harbor
  K3S_SERVER_IP=192.168.22.91 VM_PASSWORD=secret \\
    REGISTRY_URL=harbor.apps.lab.ocp.lan/nvidia \\
    DRIVER_VERSION=535.230.02 DRIVER_OS=ubuntu22.04 \\
    ./install-gpu-operator.sh

  # With 4 GPU time slices
  K3S_SERVER_IP=192.168.22.91 VM_PASSWORD=secret GPU_TIME_SLICES=4 ./install-gpu-operator.sh

  # Use pre-installed drivers (skip GPU Operator driver)
  K3S_SERVER_IP=192.168.22.91 VM_PASSWORD=secret SKIP_DRIVER=true ./install-gpu-operator.sh
EOF
        ;;
    *)
        main
        ;;
esac
