#!/bin/bash
# =============================================================================
# Install K3s Cluster on Existing VMs
# =============================================================================
#
# This script installs K3s on existing VMs. Works with:
#   - VMs created by provision-vms.sh
#   - VMs provided by someone else (just need IPs and SSH access)
#
# Supports airgapped/offline installation - downloads binaries on the jump host
# and copies them to target VMs via SCP.
#
# Usage:
#   # Option 1: Use vm-info.txt from provision-vms.sh
#   ./install-k3s.sh
#
#   # Option 2: Specify IPs directly
#   K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 ./install-k3s.sh
#
#   # Option 3: Server only (single node)
#   K3S_SERVER_IP=192.168.1.100 ./install-k3s.sh
#
# Environment Variables:
#   K3S_SERVER_IP   - IP of the K3s server node (required)
#   K3S_AGENT_IP    - IP of the K3s agent node (optional, for multi-node)
#   VM_USER         - SSH username (default: dare)
#   VM_PASSWORD     - SSH password (default: dare)
#   K3S_VERSION     - K3s version (default: v1.28.4+k3s1)
#
# =============================================================================

set -euo pipefail

# Load VM info if available
if [[ -f "vm-info.txt" ]]; then
    source vm-info.txt
fi

# Configuration
K3S_SERVER_IP="${K3S_SERVER_IP:-}"
K3S_AGENT_IP="${K3S_AGENT_IP:-}"
VM_USER="${VM_USER:-dare}"
VM_PASSWORD="${VM_PASSWORD:-dare}"
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"

# Temp directory for downloads
TEMP_DIR="/tmp/k3s-install-$$"

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

cleanup() {
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

vm_cmd() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${ip}" "$cmd"
}

vm_sudo_cmd() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${VM_USER}@${ip}" "echo '${VM_PASSWORD}' | sudo -S bash -c '$cmd'"
}

vm_copy() {
    local src="$1"
    local ip="$2"
    local dst="$3"
    sshpass -p "${VM_PASSWORD}" scp -o StrictHostKeyChecking=no -o LogLevel=ERROR "$src" "${VM_USER}@${ip}:${dst}"
}

check_prereqs() {
    log_info "Checking prerequisites..."

    if [[ -z "${K3S_SERVER_IP}" ]]; then
        log_error "K3S_SERVER_IP is required"
        log_error "Usage: K3S_SERVER_IP=192.168.1.100 ./install-k3s.sh"
        exit 1
    fi

    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required. Install with: yum install -y sshpass"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is required"
        exit 1
    fi

    log_info "Prerequisites OK"
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

download_k3s() {
    log_step "Downloading K3s ${K3S_VERSION} for offline installation..."

    mkdir -p "${TEMP_DIR}"

    if [[ ! -f "${TEMP_DIR}/k3s" ]]; then
        log_info "Downloading K3s binary..."
        curl -Lo "${TEMP_DIR}/k3s" "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s"
        chmod +x "${TEMP_DIR}/k3s"
    fi

    if [[ ! -f "${TEMP_DIR}/install.sh" ]]; then
        log_info "Downloading K3s install script..."
        curl -Lo "${TEMP_DIR}/install.sh" "https://get.k3s.io"
        chmod +x "${TEMP_DIR}/install.sh"
    fi

    # Try to download airgap images
    if [[ ! -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" && ! -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" ]]; then
        log_info "Downloading K3s airgap images..."
        curl -Lo "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar.zst" 2>/dev/null || \
        curl -Lo "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar.gz" 2>/dev/null || \
        log_warn "Could not download airgap images (may need internet on target VMs)"
    fi

    log_info "K3s downloads complete"
}

install_k3s_server() {
    local ip="$1"

    log_step "Installing K3s server on ${ip}..."

    # Copy K3s binary
    log_info "Copying K3s binary to ${ip}..."
    vm_copy "${TEMP_DIR}/k3s" "${ip}" "/tmp/k3s"
    vm_copy "${TEMP_DIR}/install.sh" "${ip}" "/tmp/install.sh"

    # Copy airgap images if available
    if [[ -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" ]]; then
        log_info "Copying airgap images..."
        vm_copy "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" "${ip}" "/tmp/k3s-airgap-images-amd64.tar.zst"
    elif [[ -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" ]]; then
        vm_copy "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" "${ip}" "/tmp/k3s-airgap-images-amd64.tar.gz"
    fi

    # Install K3s
    log_info "Installing K3s server (this may take a minute)..."
    vm_sudo_cmd "${ip}" '
        mkdir -p /usr/local/bin
        mkdir -p /var/lib/rancher/k3s/agent/images/

        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        if [[ -f /tmp/k3s-airgap-images-amd64.tar.zst ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/
        elif [[ -f /tmp/k3s-airgap-images-amd64.tar.gz ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
        fi

        INSTALL_K3S_SKIP_DOWNLOAD=true /tmp/install.sh --write-kubeconfig-mode 644

        sleep 15
        for i in {1..30}; do
            if /usr/local/bin/k3s kubectl get nodes &>/dev/null; then
                echo "K3s server is ready!"
                break
            fi
            sleep 5
        done

        /usr/local/bin/k3s kubectl get nodes
    '

    log_info "K3s server installation complete"
}

get_k3s_token() {
    local ip="$1"
    vm_sudo_cmd "${ip}" "cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null | tail -1
}

install_k3s_agent() {
    local ip="$1"
    local server_ip="$2"
    local token="$3"

    log_step "Installing K3s agent on ${ip}..."

    # Copy K3s binary
    log_info "Copying K3s binary to ${ip}..."
    vm_copy "${TEMP_DIR}/k3s" "${ip}" "/tmp/k3s"
    vm_copy "${TEMP_DIR}/install.sh" "${ip}" "/tmp/install.sh"

    # Copy airgap images if available
    if [[ -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" ]]; then
        vm_copy "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" "${ip}" "/tmp/k3s-airgap-images-amd64.tar.zst"
    elif [[ -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" ]]; then
        vm_copy "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" "${ip}" "/tmp/k3s-airgap-images-amd64.tar.gz"
    fi

    # Install K3s agent
    log_info "Installing K3s agent..."
    vm_sudo_cmd "${ip}" "
        mkdir -p /usr/local/bin
        mkdir -p /var/lib/rancher/k3s/agent/images/

        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        if [[ -f /tmp/k3s-airgap-images-amd64.tar.zst ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/
        elif [[ -f /tmp/k3s-airgap-images-amd64.tar.gz ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
        fi

        INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL='https://${server_ip}:6443' K3S_TOKEN='${token}' /tmp/install.sh

        sleep 10
        echo 'K3s agent installation complete!'
    "

    log_info "K3s agent installation complete"
}

uninstall_k3s() {
    log_step "Uninstalling K3s..."

    if [[ -n "${K3S_SERVER_IP}" ]]; then
        log_info "Uninstalling K3s from server ${K3S_SERVER_IP}..."
        vm_sudo_cmd "${K3S_SERVER_IP}" "/usr/local/bin/k3s-uninstall.sh" 2>/dev/null || true
    fi

    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "Uninstalling K3s from agent ${K3S_AGENT_IP}..."
        vm_sudo_cmd "${K3S_AGENT_IP}" "/usr/local/bin/k3s-agent-uninstall.sh" 2>/dev/null || true
    fi

    log_info "K3s uninstalled"
}

install_cluster() {
    echo ""
    log_step "=============================================="
    log_step "  Installing K3s Cluster"
    log_step "=============================================="
    echo ""
    log_info "K3s Version:   ${K3S_VERSION}"
    log_info "K3s Server:    ${K3S_SERVER_IP}"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "K3s Agent:     ${K3S_AGENT_IP}"
    else
        log_info "K3s Agent:     (none - single node cluster)"
    fi
    log_info "VM User:       ${VM_USER}"
    echo ""

    check_prereqs

    # Download K3s binaries
    download_k3s

    # Wait for SSH
    wait_for_ssh "${K3S_SERVER_IP}"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        wait_for_ssh "${K3S_AGENT_IP}"
    fi

    # Install K3s server
    install_k3s_server "${K3S_SERVER_IP}"

    # Install K3s agent if specified
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "Getting K3s join token..."
        local k3s_token=$(get_k3s_token "${K3S_SERVER_IP}")
        if [[ -z "$k3s_token" ]]; then
            log_error "Failed to get K3s token"
            exit 1
        fi
        log_info "Got K3s token"

        install_k3s_agent "${K3S_AGENT_IP}" "${K3S_SERVER_IP}" "${k3s_token}"

        # Wait for agent to join
        log_info "Waiting for agent to join cluster..."
        sleep 15
    fi

    # Verify cluster
    log_step "Verifying cluster..."
    vm_sudo_cmd "${K3S_SERVER_IP}" "/usr/local/bin/k3s kubectl get nodes -o wide"

    # Save cluster info
    cat > cluster-info.txt << EOF
K3S_SERVER_IP=${K3S_SERVER_IP}
K3S_AGENT_IP=${K3S_AGENT_IP:-}
K3S_VERSION=${K3S_VERSION}
VM_USER=${VM_USER}
EOF

    echo ""
    log_step "=============================================="
    log_step "  K3s Cluster Installed Successfully!"
    log_step "=============================================="
    echo ""
    echo "K3s Server:  ${K3S_SERVER_IP}"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        echo "K3s Agent:   ${K3S_AGENT_IP}"
    fi
    echo ""
    echo "To access the cluster:"
    echo "  ssh ${VM_USER}@${K3S_SERVER_IP}"
    echo "  sudo kubectl get nodes"
    echo ""
    echo "To get kubeconfig:"
    echo "  scp ${VM_USER}@${K3S_SERVER_IP}:/etc/rancher/k3s/k3s.yaml ./kubeconfig"
    echo "  sed -i 's/127.0.0.1/${K3S_SERVER_IP}/g' ./kubeconfig"
    echo ""
    echo "Cluster info saved to cluster-info.txt"
}

# Main
case "${1:-}" in
    --uninstall)
        check_prereqs
        uninstall_k3s
        ;;
    --help|-h)
        echo "Usage: $0 [--uninstall]"
        echo ""
        echo "Environment variables:"
        echo "  K3S_SERVER_IP  - IP of K3s server (required)"
        echo "  K3S_AGENT_IP   - IP of K3s agent (optional)"
        echo "  VM_USER        - SSH username (default: dare)"
        echo "  VM_PASSWORD    - SSH password (default: dare)"
        echo "  K3S_VERSION    - K3s version (default: v1.28.4+k3s1)"
        ;;
    *)
        install_cluster
        ;;
esac
