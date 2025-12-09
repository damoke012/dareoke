#!/bin/bash
# =============================================================================
# Provision VMs on ESXi for K3s Cluster
# =============================================================================
#
# This script creates VMs on standalone ESXi by cloning a template.
# Use this when you need to create VMs yourself.
# Skip this if VMs are provided by someone else.
#
# Usage:
#   ./provision-vms.sh [--destroy]
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
#
# Output:
#   Creates vm-info.txt with VM IPs for use with install-k3s.sh
#
# =============================================================================

set -euo pipefail

# Configuration
ESXI_HOST="${ESXI_HOST:-192.168.1.144}"
ESXI_USER="${ESXI_USER:-root}"
ESXI_PASSWORD="${ESXI_PASSWORD:-}"

TEMPLATE_NAME="${TEMPLATE_NAME:-ubuntu-template}"
K3S_SERVER_NAME="${K3S_SERVER_NAME:-k3s-server}"
K3S_AGENT_NAME="${K3S_AGENT_NAME:-k3s-gpu-agent}"
DATASTORE="${DATASTORE:-datastore1}"
DATASTORE_PATH="/vmfs/volumes/${DATASTORE}"

# VM Specs
K3S_SERVER_CPU="${K3S_SERVER_CPU:-4}"
K3S_SERVER_MEM="${K3S_SERVER_MEM:-8192}"
K3S_AGENT_CPU="${K3S_AGENT_CPU:-8}"
K3S_AGENT_MEM="${K3S_AGENT_MEM:-32768}"

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

esxi_cmd() {
    sshpass -p "${ESXI_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "${ESXI_USER}@${ESXI_HOST}" "$1"
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

clone_vm() {
    local src_name="$1"
    local dst_name="$2"
    local cpu="$3"
    local mem="$4"

    log_step "Cloning ${src_name} to ${dst_name}..."

    local existing_id=$(get_vm_id "${dst_name}")
    if [[ -n "$existing_id" ]]; then
        log_warn "VM ${dst_name} already exists (ID: ${existing_id})"
        echo "${existing_id}"
        return 0
    fi

    local src_dir="${DATASTORE_PATH}/${src_name}"
    local dst_dir="${DATASTORE_PATH}/${dst_name}"

    esxi_cmd "mkdir -p '${dst_dir}'"

    log_info "Cloning virtual disk (this may take a few minutes)..."
    esxi_cmd "vmkfstools -i '${src_dir}/${src_name}.vmdk' '${dst_dir}/${dst_name}.vmdk' -d thin"

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

    log_info "Registering VM..."
    local vmid=$(esxi_cmd "vim-cmd solo/registervm '${dst_dir}/${dst_name}.vmx'" | tr -d '[:space:]')
    log_info "VM ${dst_name} created with ID: ${vmid}"

    echo "${vmid}"
}

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

destroy_vms() {
    log_step "Destroying VMs..."

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

    rm -f vm-info.txt 2>/dev/null || true
    log_info "VMs destroyed successfully"
}

provision_vms() {
    echo ""
    log_step "=============================================="
    log_step "  Provisioning VMs for K3s Cluster"
    log_step "=============================================="
    echo ""
    log_info "ESXi Host:     ${ESXI_HOST}"
    log_info "Template:      ${TEMPLATE_NAME}"
    log_info "K3s Server:    ${K3S_SERVER_NAME} (${K3S_SERVER_CPU} CPU, ${K3S_SERVER_MEM}MB RAM)"
    log_info "K3s Agent:     ${K3S_AGENT_NAME} (${K3S_AGENT_CPU} CPU, ${K3S_AGENT_MEM}MB RAM)"
    echo ""

    check_prereqs

    # Check template exists
    local template_id=$(get_vm_id "${TEMPLATE_NAME}")
    if [[ -z "$template_id" ]]; then
        log_error "Template VM '${TEMPLATE_NAME}' not found."
        log_error "See: scripts/create-ubuntu-template.sh"
        exit 1
    fi
    log_info "Found template: ${TEMPLATE_NAME} (ID: ${template_id})"

    # Clone VMs
    local server_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_SERVER_NAME}" "${K3S_SERVER_CPU}" "${K3S_SERVER_MEM}")
    local agent_id=$(clone_vm "${TEMPLATE_NAME}" "${K3S_AGENT_NAME}" "${K3S_AGENT_CPU}" "${K3S_AGENT_MEM}")

    # Get VM IDs
    server_id=$(get_vm_id "${K3S_SERVER_NAME}")
    agent_id=$(get_vm_id "${K3S_AGENT_NAME}")

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

    # Save VM info for install-k3s.sh
    cat > vm-info.txt << EOF
K3S_SERVER_IP=${server_ip}
K3S_AGENT_IP=${agent_ip}
K3S_SERVER_NAME=${K3S_SERVER_NAME}
K3S_AGENT_NAME=${K3S_AGENT_NAME}
EOF

    echo ""
    log_step "=============================================="
    log_step "  VMs Provisioned Successfully!"
    log_step "=============================================="
    echo ""
    echo "K3s Server:  ${K3S_SERVER_NAME} (${server_ip})"
    echo "K3s Agent:   ${K3S_AGENT_NAME} (${agent_ip})"
    echo ""
    echo "VM info saved to vm-info.txt"
    echo ""
    echo "Next step - Install K3s:"
    echo "  ./install-k3s.sh"
    echo ""
    echo "Or specify IPs directly:"
    echo "  K3S_SERVER_IP=${server_ip} K3S_AGENT_IP=${agent_ip} ./install-k3s.sh"
    echo ""
}

# Main
if [[ "${1:-}" == "--destroy" ]]; then
    check_prereqs
    destroy_vms
else
    provision_vms
fi
