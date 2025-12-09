#!/bin/bash
# =============================================================================
# Deploy K3s Cluster on ESXi - Fully Automated IaC Script
# =============================================================================
#
# This script provisions and configures a K3s cluster on standalone ESXi
# without requiring vCenter. It clones VMs, configures them, and installs K3s.
#
# Usage:
#   ./deploy-k3s-cluster.sh [--destroy]
#
# Environment Variables (required):
#   ESXI_HOST       - ESXi IP address (e.g., 192.168.1.144)
#   ESXI_USER       - ESXi username (default: root)
#   ESXI_PASSWORD   - ESXi password
#   SSH_PUBLIC_KEY  - SSH public key for VM access
#
# Optional:
#   TEMPLATE_NAME   - Source template VM (default: ubuntu-template)
#   K3S_SERVER_NAME - K3s server VM name (default: k3s-server)
#   K3S_AGENT_NAME  - K3s agent VM name (default: k3s-gpu-agent)
#   DATASTORE       - ESXi datastore (default: datastore1)
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
ESXI_HOST="${ESXI_HOST:-192.168.1.144}"
ESXI_USER="${ESXI_USER:-root}"
ESXI_PASSWORD="${ESXI_PASSWORD:-}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"

TEMPLATE_NAME="${TEMPLATE_NAME:-ubuntu-template}"
K3S_SERVER_NAME="${K3S_SERVER_NAME:-k3s-server}"
K3S_AGENT_NAME="${K3S_AGENT_NAME:-k3s-gpu-agent}"
DATASTORE="${DATASTORE:-datastore1}"
DATASTORE_PATH="/vmfs/volumes/${DATASTORE}"

# VM Specs
K3S_SERVER_CPU=4
K3S_SERVER_MEM=8192
K3S_SERVER_DISK=100

K3S_AGENT_CPU=8
K3S_AGENT_MEM=32768
K3S_AGENT_DISK=200

# K3s Version
K3S_VERSION="${K3S_VERSION:-v1.28.4+k3s1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

esxi_cmd() {
    sshpass -p "${ESXI_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ESXI_USER}@${ESXI_HOST}" "$1"
}

esxi_copy() {
    sshpass -p "${ESXI_PASSWORD}" scp -o StrictHostKeyChecking=no -o LogLevel=ERROR "$1" "${ESXI_USER}@${ESXI_HOST}:$2"
}

check_prereqs() {
    log_info "Checking prerequisites..."

    if [[ -z "${ESXI_PASSWORD}" ]]; then
        log_error "ESXI_PASSWORD environment variable is required"
        exit 1
    fi

    if ! command -v sshpass &> /dev/null; then
        log_error "sshpass is required. Install with: apt install sshpass"
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
    esxi_cmd "vim-cmd vmsvc/getallvms 2>/dev/null | grep '${vm_name}' | awk '{print \$1}'" | head -1
}

get_vm_ip() {
    local vmid="$1"
    local timeout=300
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local ip=$(esxi_cmd "vim-cmd vmsvc/get.guest ${vmid} 2>/dev/null | grep -m1 'ipAddress = \"192' | sed 's/.*ipAddress = \"\([^\"]*\)\".*/\1/'" 2>/dev/null)
        if [[ -n "$ip" && "$ip" != *"unset"* ]]; then
            echo "$ip"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Waiting for VM IP... (${elapsed}s)"
    done

    log_error "Timeout waiting for VM IP"
    return 1
}

# =============================================================================
# VM Clone Function (ESXi native - no vCenter required)
# =============================================================================
clone_vm() {
    local src_name="$1"
    local dst_name="$2"
    local cpu="$3"
    local mem="$4"
    local disk_gb="$5"

    log_info "Cloning ${src_name} to ${dst_name}..."

    # Check if destination VM already exists
    local existing_id=$(get_vm_id "${dst_name}")
    if [[ -n "$existing_id" ]]; then
        log_warn "VM ${dst_name} already exists (ID: ${existing_id}). Skipping clone."
        return 0
    fi

    # Get source VM path
    local src_dir="${DATASTORE_PATH}/${src_name}"
    local dst_dir="${DATASTORE_PATH}/${dst_name}"

    # Create destination directory
    esxi_cmd "mkdir -p '${dst_dir}'"

    # Clone the VMDK (this is the disk clone)
    log_info "Cloning virtual disk (this may take a few minutes)..."
    esxi_cmd "vmkfstools -i '${src_dir}/${src_name}.vmdk' '${dst_dir}/${dst_name}.vmdk' -d thin"

    # Create new VMX file with updated specs
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
    local vmid=$(esxi_cmd "vim-cmd solo/registervm '${dst_dir}/${dst_name}.vmx'")
    log_info "VM ${dst_name} created with ID: ${vmid}"

    echo "${vmid}"
}

# =============================================================================
# Power Management
# =============================================================================
power_on_vm() {
    local vmid="$1"
    log_info "Powering on VM ${vmid}..."
    esxi_cmd "vim-cmd vmsvc/power.on ${vmid}" || true
    sleep 5
}

power_off_vm() {
    local vmid="$1"
    log_info "Powering off VM ${vmid}..."
    esxi_cmd "vim-cmd vmsvc/power.off ${vmid}" 2>/dev/null || true
    sleep 3
}

# =============================================================================
# K3s Installation
# =============================================================================
install_k3s_server() {
    local ip="$1"
    local ssh_key="$2"

    log_info "Installing K3s server on ${ip}..."

    # Wait for SSH to be available
    local timeout=120
    local elapsed=0
    while ! sshpass -p "dare" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "dare@${ip}" "echo OK" &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for SSH on ${ip}"
            return 1
        fi
        log_info "Waiting for SSH... (${elapsed}s)"
    done

    # Install K3s server
    sshpass -p "dare" ssh -o StrictHostKeyChecking=no "dare@${ip}" << ENDSSH
sudo bash -c '
# Add SSH key if provided
if [[ -n "${ssh_key}" ]]; then
    mkdir -p /root/.ssh
    echo "${ssh_key}" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Install K3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -s - \\
    --write-kubeconfig-mode 644 \\
    --disable traefik \\
    --disable servicelb

# Wait for K3s to be ready
sleep 10
until kubectl get nodes &> /dev/null; do
    echo "Waiting for K3s API..."
    sleep 5
done

kubectl wait --for=condition=Ready node --all --timeout=120s
echo "K3s server installed successfully!"
'
ENDSSH
}

get_k3s_token() {
    local ip="$1"
    sshpass -p "dare" ssh -o StrictHostKeyChecking=no "dare@${ip}" "sudo cat /var/lib/rancher/k3s/server/node-token"
}

install_k3s_agent() {
    local ip="$1"
    local server_ip="$2"
    local token="$3"
    local ssh_key="$4"

    log_info "Installing K3s agent on ${ip}..."

    # Wait for SSH
    local timeout=120
    local elapsed=0
    while ! sshpass -p "dare" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "dare@${ip}" "echo OK" &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout waiting for SSH on ${ip}"
            return 1
        fi
        log_info "Waiting for SSH... (${elapsed}s)"
    done

    # Install K3s agent
    sshpass -p "dare" ssh -o StrictHostKeyChecking=no "dare@${ip}" << ENDSSH
sudo bash -c '
# Add SSH key if provided
if [[ -n "${ssh_key}" ]]; then
    mkdir -p /root/.ssh
    echo "${ssh_key}" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Install K3s agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" \\
    K3S_URL="https://${server_ip}:6443" \\
    K3S_TOKEN="${token}" \\
    sh -

echo "K3s agent installed successfully!"
'
ENDSSH
}

# =============================================================================
# Destroy Function
# =============================================================================
destroy_cluster() {
    log_info "Destroying K3s cluster..."

    for vm_name in "${K3S_SERVER_NAME}" "${K3S_AGENT_NAME}"; do
        local vmid=$(get_vm_id "${vm_name}")
        if [[ -n "$vmid" ]]; then
            log_info "Destroying VM: ${vm_name} (ID: ${vmid})"
            power_off_vm "${vmid}"
            esxi_cmd "vim-cmd vmsvc/unregister ${vmid}" || true
            esxi_cmd "rm -rf '${DATASTORE_PATH}/${vm_name}'" || true
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
    log_info "=============================================="
    log_info "  Deploying K3s Cluster"
    log_info "=============================================="
    log_info ""
    log_info "ESXi Host:     ${ESXI_HOST}"
    log_info "Template:      ${TEMPLATE_NAME}"
    log_info "K3s Server:    ${K3S_SERVER_NAME} (${K3S_SERVER_CPU} CPU, ${K3S_SERVER_MEM}MB RAM)"
    log_info "K3s Agent:     ${K3S_AGENT_NAME} (${K3S_AGENT_CPU} CPU, ${K3S_AGENT_MEM}MB RAM)"
    log_info ""

    check_prereqs

    # Check template exists
    local template_id=$(get_vm_id "${TEMPLATE_NAME}")
    if [[ -z "$template_id" ]]; then
        log_error "Template VM '${TEMPLATE_NAME}' not found. Please create it first."
        exit 1
    fi
    log_info "Found template: ${TEMPLATE_NAME} (ID: ${template_id})"

    # Clone VMs
    local server_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_SERVER_NAME}" "${K3S_SERVER_CPU}" "${K3S_SERVER_MEM}" "${K3S_SERVER_DISK}")
    local agent_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_AGENT_NAME}" "${K3S_AGENT_CPU}" "${K3S_AGENT_MEM}" "${K3S_AGENT_DISK}")

    # Get VM IDs (in case they existed already)
    server_id=$(get_vm_id "${K3S_SERVER_NAME}")
    agent_id=$(get_vm_id "${K3S_AGENT_NAME}")

    # Power on VMs
    power_on_vm "${server_id}"
    power_on_vm "${agent_id}"

    # Get IP addresses
    log_info "Waiting for VMs to get IP addresses..."
    local server_ip=$(get_vm_ip "${server_id}")
    local agent_ip=$(get_vm_ip "${agent_id}")

    log_info "K3s Server IP: ${server_ip}"
    log_info "K3s Agent IP:  ${agent_ip}"

    # Install K3s
    install_k3s_server "${server_ip}" "${SSH_PUBLIC_KEY}"

    local k3s_token=$(get_k3s_token "${server_ip}")
    install_k3s_agent "${agent_ip}" "${server_ip}" "${k3s_token}" "${SSH_PUBLIC_KEY}"

    # Verify cluster
    log_info "Verifying cluster..."
    sleep 10
    sshpass -p "dare" ssh -o StrictHostKeyChecking=no "dare@${server_ip}" "sudo kubectl get nodes"

    # Output summary
    log_info ""
    log_info "=============================================="
    log_info "  K3s Cluster Deployed Successfully!"
    log_info "=============================================="
    log_info ""
    log_info "K3s Server:  ${K3S_SERVER_NAME} (${server_ip})"
    log_info "K3s Agent:   ${K3S_AGENT_NAME} (${agent_ip})"
    log_info ""
    log_info "To access the cluster:"
    log_info "  ssh dare@${server_ip}"
    log_info "  sudo kubectl get nodes"
    log_info ""
    log_info "To get kubeconfig:"
    log_info "  scp dare@${server_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig"
    log_info "  sed -i 's/127.0.0.1/${server_ip}/g' ./kubeconfig"
    log_info ""

    # Save outputs to file
    cat > cluster-info.txt << EOF
K3S_SERVER_NAME=${K3S_SERVER_NAME}
K3S_SERVER_IP=${server_ip}
K3S_AGENT_NAME=${K3S_AGENT_NAME}
K3S_AGENT_IP=${agent_ip}
ESXI_HOST=${ESXI_HOST}
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
