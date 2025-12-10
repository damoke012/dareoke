#!/bin/bash
# =============================================================================
# Install K3s Cluster on Existing VMs (Airgapped/Offline)
# =============================================================================
#
# This script installs K3s on existing VMs. Works with:
#   - VMs created by provision-vms.sh
#   - VMs provided by someone else (just need IPs and SSH access)
#
# Supports airgapped/offline installation - downloads binaries on the jump host
# and copies them to target VMs via SCP.
#
# IMPORTANT: Run this script from a jump host that has:
#   1. Internet access (to download K3s binaries)
#   2. SSH access to the target VMs
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
#   # Option 4: Custom hostnames
#   K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 \
#   SERVER_HOSTNAME=k3s-master AGENT_HOSTNAME=k3s-worker ./install-k3s.sh
#
# Environment Variables:
#   K3S_SERVER_IP    - IP of the K3s server node (required)
#   K3S_AGENT_IP     - IP of the K3s agent node (optional, for multi-node)
#   VM_USER          - SSH username (default: dare)
#   VM_PASSWORD      - SSH password (required, no default)
#   K3S_VERSION      - K3s version (default: v1.28.4+k3s1)
#   SERVER_HOSTNAME  - Hostname for server node (default: k3s-server)
#   AGENT_HOSTNAME   - Hostname for agent node (default: k3s-agent)
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
VM_PASSWORD="${VM_PASSWORD:-}"
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"
SERVER_HOSTNAME="${SERVER_HOSTNAME:-k3s-server}"
AGENT_HOSTNAME="${AGENT_HOSTNAME:-k3s-agent}"

# Temp directory for downloads (persistent across script runs)
TEMP_DIR="/tmp/k3s-offline-cache"

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

vm_cmd() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=10 "${VM_USER}@${ip}" "$cmd"
}

vm_sudo_cmd() {
    local ip="$1"
    local cmd="$2"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=10 "${VM_USER}@${ip}" "echo '${VM_PASSWORD}' | sudo -S bash -c '$cmd'" 2>&1 | { grep -v "^\[sudo\] password" || true; }
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
        log_error "Usage: K3S_SERVER_IP=192.168.1.100 VM_PASSWORD=yourpass ./install-k3s.sh"
        exit 1
    fi

    if [[ -z "${VM_PASSWORD}" ]]; then
        log_error "VM_PASSWORD is required"
        log_error "Usage: K3S_SERVER_IP=192.168.1.100 VM_PASSWORD=yourpass ./install-k3s.sh"
        exit 1
    fi

    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required. Install with: yum install -y sshpass (or apt install sshpass)"
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
        echo -n "."
    done
    echo ""

    log_error "Timeout waiting for SSH on ${ip}"
    return 1
}

download_k3s() {
    log_step "Downloading K3s ${K3S_VERSION} for offline installation..."

    mkdir -p "${TEMP_DIR}"

    # Check if we already have the files cached
    if [[ -f "${TEMP_DIR}/k3s-${K3S_VERSION}" ]]; then
        log_info "Using cached K3s binary"
        cp "${TEMP_DIR}/k3s-${K3S_VERSION}" "${TEMP_DIR}/k3s"
    else
        log_info "Downloading K3s binary..."
        curl -fLo "${TEMP_DIR}/k3s" "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s"
        chmod +x "${TEMP_DIR}/k3s"
        # Cache for future use
        cp "${TEMP_DIR}/k3s" "${TEMP_DIR}/k3s-${K3S_VERSION}"
    fi

    if [[ ! -f "${TEMP_DIR}/install.sh" ]]; then
        log_info "Downloading K3s install script..."
        curl -fLo "${TEMP_DIR}/install.sh" "https://get.k3s.io"
        chmod +x "${TEMP_DIR}/install.sh"
    fi

    log_info "K3s downloads complete"
}

set_hostname() {
    local ip="$1"
    local hostname="$2"

    log_info "Setting hostname to ${hostname} on ${ip}..."
    vm_sudo_cmd "${ip}" "hostnamectl set-hostname ${hostname}"
}

cleanup_k3s() {
    local ip="$1"
    local type="$2"  # "server" or "agent"

    log_info "Cleaning up any existing K3s installation on ${ip}..."

    if [[ "$type" == "server" ]]; then
        vm_sudo_cmd "${ip}" "/usr/local/bin/k3s-uninstall.sh 2>/dev/null || true"
    else
        vm_sudo_cmd "${ip}" "/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true"
    fi

    # Clean up any leftover files
    vm_sudo_cmd "${ip}" "rm -rf /etc/rancher/node /var/lib/rancher/k3s 2>/dev/null || true"
}

install_k3s_server() {
    local ip="$1"
    local hostname="$2"

    log_step "Installing K3s server on ${ip} (hostname: ${hostname})..."

    # Set hostname first to avoid duplicate hostname issues
    set_hostname "${ip}" "${hostname}"

    # Clean up any existing installation
    cleanup_k3s "${ip}" "server"

    # Copy K3s binary
    log_info "Copying K3s binary to ${ip}..."
    vm_copy "${TEMP_DIR}/k3s" "${ip}" "/tmp/k3s"
    vm_copy "${TEMP_DIR}/install.sh" "${ip}" "/tmp/install.sh"

    # Install K3s
    log_info "Installing K3s server (this may take a minute)..."
    vm_sudo_cmd "${ip}" '
        mkdir -p /usr/local/bin

        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        INSTALL_K3S_SKIP_DOWNLOAD=true /tmp/install.sh --write-kubeconfig-mode 644
    '

    # Wait for K3s to be ready
    log_info "Waiting for K3s server to be ready..."
    local retries=30
    for ((i=1; i<=retries; i++)); do
        if vm_sudo_cmd "${ip}" "/usr/local/bin/k3s kubectl get nodes" &>/dev/null; then
            log_info "K3s server is ready!"
            return 0
        fi
        sleep 5
        echo -n "."
    done
    echo ""

    log_error "K3s server failed to become ready"
    return 1
}

get_k3s_token() {
    local ip="$1"
    local token=""
    local retries=10

    for ((i=1; i<=retries; i++)); do
        token=$(vm_sudo_cmd "${ip}" "cat /var/lib/rancher/k3s/server/node-token 2>/dev/null" | { grep -v "^\[sudo\]" || true; } | tail -1) || true
        if [[ -n "$token" && "$token" == K* ]]; then
            echo "$token"
            return 0
        fi
        # Print to stderr so it doesn't get captured in command substitution
        echo -e "${GREEN}[INFO]${NC} Waiting for token (attempt $i/$retries)..." >&2
        sleep 3
    done

    echo -e "${RED}[ERROR]${NC} Failed to retrieve K3s token after $retries attempts" >&2
    echo ""
    return 0
}

install_k3s_agent() {
    local ip="$1"
    local server_ip="$2"
    local token="$3"
    local hostname="$4"

    log_step "Installing K3s agent on ${ip} (hostname: ${hostname})..."

    # Set hostname first to avoid duplicate hostname issues
    set_hostname "${ip}" "${hostname}"

    # Clean up any existing installation
    cleanup_k3s "${ip}" "agent"

    # Copy K3s binary
    log_info "Copying K3s binary to ${ip}..."
    vm_copy "${TEMP_DIR}/k3s" "${ip}" "/tmp/k3s"
    vm_copy "${TEMP_DIR}/install.sh" "${ip}" "/tmp/install.sh"

    # Install K3s agent
    log_info "Installing K3s agent..."
    vm_sudo_cmd "${ip}" "
        mkdir -p /usr/local/bin

        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL='https://${server_ip}:6443' K3S_TOKEN='${token}' /tmp/install.sh
    "

    log_info "K3s agent installation complete"
}

wait_for_agent() {
    local server_ip="$1"
    local agent_hostname="$2"
    local retries=30

    log_info "Waiting for agent ${agent_hostname} to join cluster..."
    for ((i=1; i<=retries; i++)); do
        local status=$(vm_sudo_cmd "${server_ip}" "/usr/local/bin/k3s kubectl get node ${agent_hostname} -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null" || echo "")
        if [[ "$status" == "True" ]]; then
            log_info "Agent ${agent_hostname} is Ready!"
            return 0
        fi
        sleep 5
        echo -n "."
    done
    echo ""

    log_warn "Agent may still be initializing. Check manually with: kubectl get nodes"
    return 0
}

uninstall_k3s() {
    log_step "Uninstalling K3s..."

    if [[ -n "${K3S_SERVER_IP}" ]]; then
        log_info "Uninstalling K3s from server ${K3S_SERVER_IP}..."
        cleanup_k3s "${K3S_SERVER_IP}" "server"
    fi

    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "Uninstalling K3s from agent ${K3S_AGENT_IP}..."
        cleanup_k3s "${K3S_AGENT_IP}" "agent"
    fi

    log_info "K3s uninstalled"
}

install_cluster() {
    echo ""
    log_step "=============================================="
    log_step "  K3s Cluster Installation (Airgapped)"
    log_step "=============================================="
    echo ""
    log_info "K3s Version:      ${K3S_VERSION}"
    log_info "K3s Server:       ${K3S_SERVER_IP} (hostname: ${SERVER_HOSTNAME})"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "K3s Agent:        ${K3S_AGENT_IP} (hostname: ${AGENT_HOSTNAME})"
    else
        log_info "K3s Agent:        (none - single node cluster)"
    fi
    log_info "VM User:          ${VM_USER}"
    echo ""

    check_prereqs

    # Download K3s binaries (on jump host)
    download_k3s

    # Wait for SSH access
    wait_for_ssh "${K3S_SERVER_IP}"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        wait_for_ssh "${K3S_AGENT_IP}"
    fi

    # Install K3s server
    install_k3s_server "${K3S_SERVER_IP}" "${SERVER_HOSTNAME}"

    # Install K3s agent if specified
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        log_info "Getting K3s join token..."
        local k3s_token
        k3s_token=$(get_k3s_token "${K3S_SERVER_IP}")
        if [[ -z "$k3s_token" ]]; then
            log_error "Failed to get K3s token from server"
            exit 1
        fi
        log_info "Got K3s token"

        install_k3s_agent "${K3S_AGENT_IP}" "${K3S_SERVER_IP}" "${k3s_token}" "${AGENT_HOSTNAME}"

        # Wait for agent to join
        wait_for_agent "${K3S_SERVER_IP}" "${AGENT_HOSTNAME}"
    fi

    # Verify cluster
    echo ""
    log_step "Cluster Status:"
    vm_sudo_cmd "${K3S_SERVER_IP}" "/usr/local/bin/k3s kubectl get nodes -o wide"

    # Save cluster info
    cat > cluster-info.txt << EOF
# K3s Cluster Information
# Generated: $(date)

K3S_SERVER_IP=${K3S_SERVER_IP}
K3S_AGENT_IP=${K3S_AGENT_IP:-}
K3S_VERSION=${K3S_VERSION}
VM_USER=${VM_USER}
SERVER_HOSTNAME=${SERVER_HOSTNAME}
AGENT_HOSTNAME=${AGENT_HOSTNAME}
EOF

    echo ""
    log_step "=============================================="
    log_step "  K3s Cluster Installed Successfully!"
    log_step "=============================================="
    echo ""
    echo "K3s Server:  ${K3S_SERVER_IP} (${SERVER_HOSTNAME})"
    if [[ -n "${K3S_AGENT_IP}" ]]; then
        echo "K3s Agent:   ${K3S_AGENT_IP} (${AGENT_HOSTNAME})"
    fi
    echo ""
    echo "To access the cluster:"
    echo "  ssh ${VM_USER}@${K3S_SERVER_IP}"
    echo "  sudo kubectl get nodes"
    echo ""
    echo "To get kubeconfig for remote access:"
    echo "  scp ${VM_USER}@${K3S_SERVER_IP}:/etc/rancher/k3s/k3s.yaml ./kubeconfig"
    echo "  sed -i 's/127.0.0.1/${K3S_SERVER_IP}/g' ./kubeconfig"
    echo "  export KUBECONFIG=./kubeconfig"
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
        cat << EOF
K3s Cluster Installer (Airgapped/Offline)

Usage: $0 [OPTIONS]

Options:
  --uninstall    Uninstall K3s from the VMs
  --help, -h     Show this help message

Environment Variables (required):
  K3S_SERVER_IP    IP address of the K3s server node
  VM_PASSWORD      SSH password for the VMs

Environment Variables (optional):
  K3S_AGENT_IP     IP address of the K3s agent node (for multi-node)
  VM_USER          SSH username (default: dare)
  K3S_VERSION      K3s version (default: v1.28.4+k3s1)
  SERVER_HOSTNAME  Hostname for server (default: k3s-server)
  AGENT_HOSTNAME   Hostname for agent (default: k3s-agent)

Examples:
  # Single node cluster
  K3S_SERVER_IP=192.168.1.100 VM_PASSWORD=secret ./install-k3s.sh

  # Two node cluster
  K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret ./install-k3s.sh

  # Custom hostnames
  K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 \\
  VM_PASSWORD=secret SERVER_HOSTNAME=master AGENT_HOSTNAME=worker ./install-k3s.sh

  # Uninstall
  K3S_SERVER_IP=192.168.1.100 K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret ./install-k3s.sh --uninstall
EOF
        ;;
    *)
        install_cluster
        ;;
esac
