#!/bin/bash
# =============================================================================
# Deploy K3s Cluster on ESXi - Fully Automated IaC Script
# =============================================================================
#
# This script provisions and configures a K3s cluster on standalone ESXi
# without requiring vCenter. It clones VMs, configures them, and installs K3s.
#
# Supports airgapped/offline installation for VMs without internet access.
#
# Usage:
#   ./deploy-k3s-cluster.sh [--destroy]
#
# Environment Variables (required):
#   ESXI_HOST       - ESXi IP address (e.g., 192.168.1.144)
#   ESXI_PASSWORD   - ESXi password
#
# Optional:
#   ESXI_USER       - ESXi username (default: root)
#   TEMPLATE_NAME   - Source template VM (default: ubuntu-template)
#   K3S_SERVER_NAME - K3s server VM name (default: k3s-server)
#   K3S_AGENT_NAME  - K3s agent VM name (default: k3s-gpu-agent)
#   VM_USER         - VM SSH user (default: dare)
#   VM_PASSWORD     - VM SSH password (default: dare)
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
ESXI_HOST="${ESXI_HOST:-192.168.1.144}"
ESXI_USER="${ESXI_USER:-root}"
ESXI_PASSWORD="${ESXI_PASSWORD:-}"

TEMPLATE_NAME="${TEMPLATE_NAME:-ubuntu-template}"
K3S_SERVER_NAME="${K3S_SERVER_NAME:-k3s-server}"
K3S_AGENT_NAME="${K3S_AGENT_NAME:-k3s-gpu-agent}"
DATASTORE="${DATASTORE:-datastore1}"
DATASTORE_PATH="/vmfs/volumes/${DATASTORE}"

# VM credentials (from template)
VM_USER="${VM_USER:-dare}"
VM_PASSWORD="${VM_PASSWORD:-dare}"

# VM Specs
K3S_SERVER_CPU=4
K3S_SERVER_MEM=8192

K3S_AGENT_CPU=8
K3S_AGENT_MEM=32768

# K3s Version
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"

# Temp directory for downloads
TEMP_DIR="/tmp/k3s-deploy-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

cleanup() {
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

esxi_cmd() {
    sshpass -p "${ESXI_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ESXI_USER}@${ESXI_HOST}" "$1"
}

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

    if [[ -z "${ESXI_PASSWORD}" ]]; then
        log_error "ESXI_PASSWORD environment variable is required"
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

    # Test ESXi connectivity
    if ! esxi_cmd "echo OK" &> /dev/null; then
        log_error "Cannot connect to ESXi at ${ESXI_HOST}"
        exit 1
    fi

    log_info "Prerequisites OK"
}

get_vm_id() {
    local vm_name="$1"
    local result=$(esxi_cmd "vim-cmd vmsvc/getallvms 2>/dev/null | grep -w '${vm_name}' | awk '{print \$1}'" 2>/dev/null)
    echo "$result" | head -1 | tr -d '[:space:]'
}

get_vm_ip() {
    local vmid="$1"
    local timeout=180
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local ip=$(esxi_cmd "vim-cmd vmsvc/get.guest ${vmid} 2>/dev/null | grep -oP 'ipAddress = \"192\\.168\\.[0-9]+\\.[0-9]+\"' | head -1 | grep -oP '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+'" 2>/dev/null | head -1)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo -ne "\r[INFO] Waiting for VM IP... (${elapsed}s)    " >&2
    done

    echo "" >&2
    log_error "Timeout waiting for VM IP"
    return 1
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

# =============================================================================
# Download K3s for Offline Installation
# =============================================================================
download_k3s() {
    log_step "Downloading K3s ${K3S_VERSION} for offline installation..."

    mkdir -p "${TEMP_DIR}"

    # Download K3s binary
    if [[ ! -f "${TEMP_DIR}/k3s" ]]; then
        log_info "Downloading K3s binary..."
        curl -Lo "${TEMP_DIR}/k3s" "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s"
        chmod +x "${TEMP_DIR}/k3s"
    fi

    # Download install script
    if [[ ! -f "${TEMP_DIR}/install.sh" ]]; then
        log_info "Downloading K3s install script..."
        curl -Lo "${TEMP_DIR}/install.sh" "https://get.k3s.io"
        chmod +x "${TEMP_DIR}/install.sh"
    fi

    # Download K3s airgap images (optional but recommended)
    if [[ ! -f "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" ]]; then
        log_info "Downloading K3s airgap images..."
        curl -Lo "${TEMP_DIR}/k3s-airgap-images-amd64.tar.zst" \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar.zst" 2>/dev/null || \
        curl -Lo "${TEMP_DIR}/k3s-airgap-images-amd64.tar.gz" \
            "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-airgap-images-amd64.tar.gz" 2>/dev/null || \
        log_warn "Could not download airgap images (will try online install)"
    fi

    log_info "K3s downloads complete"
}

# =============================================================================
# VM Clone Function
# =============================================================================
clone_vm() {
    local src_name="$1"
    local dst_name="$2"
    local cpu="$3"
    local mem="$4"

    log_step "Cloning ${src_name} to ${dst_name}..."

    # Check if destination VM already exists
    local existing_id=$(get_vm_id "${dst_name}")
    if [[ -n "$existing_id" ]]; then
        log_warn "VM ${dst_name} already exists (ID: ${existing_id})"
        echo "${existing_id}"
        return 0
    fi

    local src_dir="${DATASTORE_PATH}/${src_name}"
    local dst_dir="${DATASTORE_PATH}/${dst_name}"

    # Create destination directory
    esxi_cmd "mkdir -p '${dst_dir}'"

    # Clone the VMDK
    log_info "Cloning virtual disk (this may take a few minutes)..."
    esxi_cmd "vmkfstools -i '${src_dir}/${src_name}.vmdk' '${dst_dir}/${dst_name}.vmdk' -d thin"

    # Create VMX file
    log_info "Creating VM configuration..."
    esxi_cmd "cat > '${dst_dir}/${dst_name}.vmx' << 'VMXEOF'
.encoding = \"UTF-8\"
config.version = \"8\"
virtualHW.version = \"21\"
pciBridge0.present = \"TRUE\"
pciBridge4.present = \"TRUE\"
pciBridge4.virtualDev = \"pcieRootPort\"
pciBridge4.functions = \"8\"
vmci0.present = \"TRUE\"
hpet0.present = \"TRUE\"
displayName = \"${dst_name}\"
guestOS = \"ubuntu-64\"
memSize = \"${mem}\"
numvcpus = \"${cpu}\"
scsi0.virtualDev = \"pvscsi\"
scsi0.present = \"TRUE\"
scsi0:0.fileName = \"${dst_name}.vmdk\"
scsi0:0.present = \"TRUE\"
ethernet0.virtualDev = \"vmxnet3\"
ethernet0.networkName = \"VM Network\"
ethernet0.addressType = \"generated\"
ethernet0.present = \"TRUE\"
tools.syncTime = \"TRUE\"
VMXEOF"

    # Register the VM
    log_info "Registering VM..."
    local vmid=$(esxi_cmd "vim-cmd solo/registervm '${dst_dir}/${dst_name}.vmx'" | tr -d '[:space:]')
    log_info "VM ${dst_name} created with ID: ${vmid}"

    echo "${vmid}"
}

# =============================================================================
# Install K3s (Offline)
# =============================================================================
install_k3s_server_offline() {
    local ip="$1"

    log_step "Installing K3s server on ${ip} (offline mode)..."

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
    log_info "Installing K3s server..."
    vm_sudo_cmd "${ip}" "
        # Create directories
        mkdir -p /usr/local/bin
        mkdir -p /var/lib/rancher/k3s/agent/images/

        # Install K3s binary
        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        # Install airgap images if available
        if [[ -f /tmp/k3s-airgap-images-amd64.tar.zst ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/
        elif [[ -f /tmp/k3s-airgap-images-amd64.tar.gz ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
        fi

        # Run install script with offline binary
        INSTALL_K3S_SKIP_DOWNLOAD=true /tmp/install.sh --write-kubeconfig-mode 644

        # Wait for K3s to be ready
        sleep 15
        for i in {1..30}; do
            if /usr/local/bin/k3s kubectl get nodes &>/dev/null; then
                echo 'K3s server is ready!'
                break
            fi
            sleep 5
        done

        /usr/local/bin/k3s kubectl get nodes
    "

    log_info "K3s server installation complete on ${ip}"
}

get_k3s_token() {
    local ip="$1"
    vm_sudo_cmd "${ip}" "cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null | tail -1
}

install_k3s_agent_offline() {
    local ip="$1"
    local server_ip="$2"
    local token="$3"

    log_step "Installing K3s agent on ${ip} (offline mode)..."

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
        # Create directories
        mkdir -p /usr/local/bin
        mkdir -p /var/lib/rancher/k3s/agent/images/

        # Install K3s binary
        cp /tmp/k3s /usr/local/bin/k3s
        chmod +x /usr/local/bin/k3s

        # Install airgap images if available
        if [[ -f /tmp/k3s-airgap-images-amd64.tar.zst ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.zst /var/lib/rancher/k3s/agent/images/
        elif [[ -f /tmp/k3s-airgap-images-amd64.tar.gz ]]; then
            cp /tmp/k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/
        fi

        # Run install script with offline binary
        INSTALL_K3S_SKIP_DOWNLOAD=true K3S_URL='https://${server_ip}:6443' K3S_TOKEN='${token}' /tmp/install.sh

        sleep 10
        echo 'K3s agent installation complete!'
    "

    log_info "K3s agent installation complete on ${ip}"
}

# =============================================================================
# Power Management
# =============================================================================
power_on_vm() {
    local vmid="$1"
    log_info "Powering on VM ${vmid}..."
    esxi_cmd "vim-cmd vmsvc/power.on ${vmid}" 2>/dev/null || true
    sleep 5
}

power_off_vm() {
    local vmid="$1"
    log_info "Powering off VM ${vmid}..."
    esxi_cmd "vim-cmd vmsvc/power.off ${vmid}" 2>/dev/null || true
    sleep 3
}

# =============================================================================
# Destroy Function
# =============================================================================
destroy_cluster() {
    log_step "Destroying K3s cluster..."

    for vm_name in "${K3S_SERVER_NAME}" "${K3S_AGENT_NAME}"; do
        local vmid=$(get_vm_id "${vm_name}")
        if [[ -n "$vmid" ]]; then
            log_info "Destroying VM: ${vm_name} (ID: ${vmid})"
            power_off_vm "${vmid}"
            sleep 2
            esxi_cmd "vim-cmd vmsvc/unregister ${vmid}" 2>/dev/null || true
            esxi_cmd "rm -rf '${DATASTORE_PATH}/${vm_name}'" 2>/dev/null || true
            log_info "VM ${vm_name} destroyed"
        else
            log_warn "VM ${vm_name} not found, skipping"
        fi
    done

    log_info "Cluster destroyed successfully"
}

# =============================================================================
# Main Deployment
# =============================================================================
deploy_cluster() {
    echo ""
    log_step "=============================================="
    log_step "  Deploying K3s Cluster (Offline Mode)"
    log_step "=============================================="
    echo ""
    log_info "ESXi Host:     ${ESXI_HOST}"
    log_info "Template:      ${TEMPLATE_NAME}"
    log_info "K3s Server:    ${K3S_SERVER_NAME} (${K3S_SERVER_CPU} CPU, ${K3S_SERVER_MEM}MB RAM)"
    log_info "K3s Agent:     ${K3S_AGENT_NAME} (${K3S_AGENT_CPU} CPU, ${K3S_AGENT_MEM}MB RAM)"
    log_info "K3s Version:   ${K3S_VERSION}"
    log_info "VM User:       ${VM_USER}"
    echo ""

    check_prereqs

    # Check template exists
    local template_id=$(get_vm_id "${TEMPLATE_NAME}")
    if [[ -z "$template_id" ]]; then
        log_error "Template VM '${TEMPLATE_NAME}' not found. Please create it first."
        log_error "See: scripts/create-ubuntu-template.sh"
        exit 1
    fi
    log_info "Found template: ${TEMPLATE_NAME} (ID: ${template_id})"

    # Download K3s binaries (on this machine which has internet)
    download_k3s

    # Clone VMs
    local server_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_SERVER_NAME}" "${K3S_SERVER_CPU}" "${K3S_SERVER_MEM}")
    local agent_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_AGENT_NAME}" "${K3S_AGENT_CPU}" "${K3S_AGENT_MEM}")

    # Get VM IDs (in case they existed already)
    server_id=$(get_vm_id "${K3S_SERVER_NAME}")
    agent_id=$(get_vm_id "${K3S_AGENT_NAME}")

    log_info "K3s Server VM ID: ${server_id}"
    log_info "K3s Agent VM ID: ${agent_id}"

    # Power on VMs
    power_on_vm "${server_id}"
    power_on_vm "${agent_id}"

    # Get IP addresses
    echo ""
    log_step "Waiting for VMs to get IP addresses..."
    local server_ip=$(get_vm_ip "${server_id}")
    echo ""
    log_info "K3s Server IP: ${server_ip}"

    local agent_ip=$(get_vm_ip "${agent_id}")
    echo ""
    log_info "K3s Agent IP:  ${agent_ip}"

    # Wait for SSH
    wait_for_ssh "${server_ip}"
    wait_for_ssh "${agent_ip}"

    # Install K3s server (offline)
    install_k3s_server_offline "${server_ip}"

    # Get token and install agent
    log_info "Getting K3s join token..."
    local k3s_token=$(get_k3s_token "${server_ip}")
    if [[ -z "$k3s_token" ]]; then
        log_error "Failed to get K3s token"
        exit 1
    fi
    log_info "Got K3s token"

    install_k3s_agent_offline "${agent_ip}" "${server_ip}" "${k3s_token}"

    # Wait for agent to join
    log_info "Waiting for agent to join cluster..."
    sleep 15

    # Verify cluster
    log_step "Verifying cluster..."
    vm_sudo_cmd "${server_ip}" "/usr/local/bin/k3s kubectl get nodes -o wide"

    # Output summary
    echo ""
    log_step "=============================================="
    log_step "  K3s Cluster Deployed Successfully!"
    log_step "=============================================="
    echo ""
    echo "K3s Server:  ${K3S_SERVER_NAME} (${server_ip})"
    echo "K3s Agent:   ${K3S_AGENT_NAME} (${agent_ip})"
    echo ""
    echo "To access the cluster:"
    echo "  ssh ${VM_USER}@${server_ip}"
    echo "  sudo kubectl get nodes"
    echo ""
    echo "To get kubeconfig:"
    echo "  scp ${VM_USER}@${server_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig"
    echo "  sed -i 's/127.0.0.1/${server_ip}/g' ./kubeconfig"
    echo ""

    # Save outputs to file
    cat > cluster-info.txt << EOF
K3S_SERVER_NAME=${K3S_SERVER_NAME}
K3S_SERVER_IP=${server_ip}
K3S_SERVER_ID=${server_id}
K3S_AGENT_NAME=${K3S_AGENT_NAME}
K3S_AGENT_IP=${agent_ip}
K3S_AGENT_ID=${agent_id}
ESXI_HOST=${ESXI_HOST}
K3S_VERSION=${K3S_VERSION}
VM_USER=${VM_USER}
EOF
    log_info "Cluster info saved to cluster-info.txt"
}

# =============================================================================
# Main
# =============================================================================
main() {
    if [[ "${1:-}" == "--destroy" ]]; then
        check_prereqs
        destroy_cluster
    else
        deploy_cluster
    fi
}

main "$@"
