#!/bin/bash
# =============================================================================
# Provision VMs on ESXi for K3s Cluster
# =============================================================================
#
# This script creates VMs on standalone ESXi by cloning a template.
# Use this when you need to create VMs yourself.
# Skip this if VMs are provided by someone else.
#
# IMPORTANT: GPU Agent VMs use EFI firmware for proper 64-bit BAR mapping.
# This is REQUIRED for Tesla P40 and other GPUs with large BARs (>4GB).
# BIOS-based VMs cannot allocate 64-bit address space for large GPU BARs.
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
#   GPU_PASSTHRU_ID - GPU PCI passthrough ID (e.g., 0:66:0.0)
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
K3S_AGENT_MEM="${K3S_AGENT_MEM:-16384}"

# GPU Passthrough Settings
# To find the correct ID, run on ESXi: lspci | grep -i nvidia
# Then convert hex bus to decimal: 0x42 = 66, so 0000:42:00.0 becomes 0:66:0.0
GPU_PASSTHRU_ID="${GPU_PASSTHRU_ID:-}"
GPU_DEVICE_ID="${GPU_DEVICE_ID:-0x1b38}"     # Tesla P40 = 0x1b38
GPU_VENDOR_ID="${GPU_VENDOR_ID:-0x10de}"     # NVIDIA = 0x10de
GPU_SYSTEM_ID="${GPU_SYSTEM_ID:-}"           # Will be auto-detected from ESXi

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

# Clone a standard VM (BIOS-based, for K3s server)
clone_vm_bios() {
    local src_name="$1"
    local dst_name="$2"
    local cpu="$3"
    local mem="$4"

    log_step "Cloning ${src_name} to ${dst_name} (BIOS)..."

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

    log_info "Creating VM configuration (BIOS)..."
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
scsi0.virtualDev = \"lsilogic\"
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

# Clone a GPU VM (EFI-based, REQUIRED for large BAR GPUs like Tesla P40)
# EFI firmware properly allocates 64-bit address space for GPU BAR1 (32GB)
clone_vm_efi_gpu() {
    local src_name="$1"
    local dst_name="$2"
    local cpu="$3"
    local mem="$4"

    log_step "Cloning ${src_name} to ${dst_name} (EFI + GPU)..."

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

    log_info "Creating VM configuration (EFI + GPU passthrough)..."
    # EFI firmware is CRITICAL for 64-bit BAR mapping
    # Without EFI, large GPU BARs (>4GB) show as <unassigned> in guest
    esxi_cmd "cat > '${dst_dir}/${dst_name}.vmx' << 'VMXEOF'
.encoding = \"UTF-8\"
config.version = \"8\"
virtualHW.version = \"21\"
displayName = \"${dst_name}\"
guestOS = \"ubuntu-64\"
firmware = \"efi\"
numvcpus = \"${cpu}\"
memSize = \"${mem}\"
sched.mem.min = \"${mem}\"
sched.mem.minSize = \"${mem}\"
sched.mem.pin = \"TRUE\"
pciBridge0.present = \"TRUE\"
pciBridge4.present = \"TRUE\"
pciBridge4.virtualDev = \"pcieRootPort\"
pciBridge4.functions = \"8\"
pciBridge5.present = \"TRUE\"
pciBridge5.virtualDev = \"pcieRootPort\"
pciBridge5.functions = \"8\"
pciBridge6.present = \"TRUE\"
pciBridge6.virtualDev = \"pcieRootPort\"
pciBridge6.functions = \"8\"
pciBridge7.present = \"TRUE\"
pciBridge7.virtualDev = \"pcieRootPort\"
pciBridge7.functions = \"8\"
vmci0.present = \"TRUE\"
hpet0.present = \"TRUE\"
scsi0.present = \"TRUE\"
scsi0.virtualDev = \"lsilogic\"
scsi0:0.present = \"TRUE\"
scsi0:0.fileName = \"${dst_name}.vmdk\"
ethernet0.present = \"TRUE\"
ethernet0.virtualDev = \"vmxnet3\"
ethernet0.networkName = \"VM Network\"
ethernet0.addressType = \"generated\"
pciPassthru.use64bitMMIO = \"TRUE\"
pciPassthru.64bitMMIOSizeGB = \"128\"
hypervisor.cpuid.v0 = \"FALSE\"
tools.syncTime = \"TRUE\"
VMXEOF"

    log_info "Registering VM..."
    local vmid=$(esxi_cmd "vim-cmd solo/registervm '${dst_dir}/${dst_name}.vmx'" | tr -d '[:space:]')
    log_info "VM ${dst_name} created with ID: ${vmid}"

    echo "${vmid}"
}

# Add GPU passthrough to an existing VM
# Must be run when VM is powered off
add_gpu_passthrough() {
    local vmid="$1"
    local vm_name="$2"
    local passthru_id="$3"

    if [[ -z "$passthru_id" ]]; then
        log_warn "No GPU_PASSTHRU_ID specified, skipping GPU passthrough configuration"
        log_warn "To add GPU later, run: GPU_PASSTHRU_ID=0:66:0.0 ./provision-vms.sh --add-gpu <vmid>"
        return 0
    fi

    log_step "Adding GPU passthrough to ${vm_name}..."

    local dst_dir="${DATASTORE_PATH}/${vm_name}"

    # Get ESXi system ID for passthrough
    local system_id=$(esxi_cmd "esxcli system uuid get" | tr -d '[:space:]')

    log_info "Adding PCI passthrough device: ${passthru_id}"
    esxi_cmd "cat >> '${dst_dir}/${vm_name}.vmx' << 'VMXEOF'
pciPassthru0.present = \"TRUE\"
pciPassthru0.id = \"${passthru_id}\"
pciPassthru0.deviceId = \"${GPU_DEVICE_ID}\"
pciPassthru0.vendorId = \"${GPU_VENDOR_ID}\"
pciPassthru0.systemId = \"${system_id}\"
VMXEOF"

    # Reload VM config
    esxi_cmd "vim-cmd vmsvc/reload ${vmid}" 2>/dev/null || true

    log_info "GPU passthrough configured for ${vm_name}"
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
    log_info "K3s Server:    ${K3S_SERVER_NAME} (${K3S_SERVER_CPU} CPU, ${K3S_SERVER_MEM}MB RAM) [BIOS]"
    log_info "K3s Agent:     ${K3S_AGENT_NAME} (${K3S_AGENT_CPU} CPU, ${K3S_AGENT_MEM}MB RAM) [EFI+GPU]"
    if [[ -n "${GPU_PASSTHRU_ID}" ]]; then
        log_info "GPU Passthru:  ${GPU_PASSTHRU_ID}"
    else
        log_warn "GPU Passthru:  Not configured (set GPU_PASSTHRU_ID to enable)"
    fi
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

    # Clone K3s Server (BIOS - no GPU needed)
    local server_id=$(clone_vm_bios "${TEMPLATE_NAME}" "${K3S_SERVER_NAME}" "${K3S_SERVER_CPU}" "${K3S_SERVER_MEM}")

    # Clone K3s GPU Agent (EFI - REQUIRED for large BAR GPUs)
    local agent_id=$(clone_vm_efi_gpu "${TEMPLATE_NAME}" "${K3S_AGENT_NAME}" "${K3S_AGENT_CPU}" "${K3S_AGENT_MEM}")

    # Get VM IDs
    server_id=$(get_vm_id "${K3S_SERVER_NAME}")
    agent_id=$(get_vm_id "${K3S_AGENT_NAME}")

    # Add GPU passthrough to agent if configured
    if [[ -n "${GPU_PASSTHRU_ID}" ]]; then
        add_gpu_passthrough "${agent_id}" "${K3S_AGENT_NAME}" "${GPU_PASSTHRU_ID}"
    fi

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
    echo "K3s Server:  ${K3S_SERVER_NAME} (${server_ip}) [BIOS]"
    echo "K3s Agent:   ${K3S_AGENT_NAME} (${agent_ip}) [EFI+GPU]"
    echo ""
    echo "IMPORTANT: GPU Agent uses EFI firmware for proper 64-bit BAR mapping."
    echo "This is REQUIRED for Tesla P40 and other large BAR GPUs."
    echo ""
    echo "VM info saved to vm-info.txt"
    echo ""
    echo "Next steps:"
    echo "  1. Install OS on VMs (if not cloned from installed template)"
    echo "  2. Setup GPU node: ./setup-gpu-node.sh --remote"
    echo "  3. Install K3s: ./install-k3s.sh"
    echo ""
    if [[ -z "${GPU_PASSTHRU_ID}" ]]; then
        echo "To add GPU passthrough later:"
        echo "  GPU_PASSTHRU_ID=0:66:0.0 ./provision-vms.sh --add-gpu ${K3S_AGENT_NAME}"
        echo ""
    fi
}

# Show help
show_help() {
    cat << 'EOF'
Provision VMs for K3s Cluster on ESXi

IMPORTANT: GPU Agent VMs use EFI firmware for proper 64-bit BAR mapping.
This is REQUIRED for Tesla P40 and other GPUs with large BARs (>4GB).

Usage:
  ./provision-vms.sh              Create VMs
  ./provision-vms.sh --destroy    Destroy VMs
  ./provision-vms.sh --add-gpu    Add GPU passthrough to existing VM
  ./provision-vms.sh --help       Show this help

Environment Variables (required):
  ESXI_HOST       - ESXi IP address (e.g., 192.168.1.144)
  ESXI_PASSWORD   - ESXi root password

Environment Variables (optional):
  TEMPLATE_NAME   - Source template VM (default: ubuntu-template)
  K3S_SERVER_NAME - K3s server VM name (default: k3s-server)
  K3S_AGENT_NAME  - K3s GPU agent VM name (default: k3s-gpu-agent)
  GPU_PASSTHRU_ID - GPU PCI passthrough ID (e.g., 0:66:0.0)
  GPU_DEVICE_ID   - GPU PCI device ID (default: 0x1b38 for Tesla P40)
  GPU_VENDOR_ID   - GPU PCI vendor ID (default: 0x10de for NVIDIA)

Finding GPU Passthrough ID:
  1. SSH to ESXi: ssh root@<esxi-host>
  2. Find GPU: lspci | grep -i nvidia
     Output: 0000:42:00.0 3D controller: NVIDIA Corporation...
  3. Convert hex bus to decimal: 0x42 = 66
  4. Format: 0:66:0.0 (bus 66, slot 0, function 0)

Examples:
  # Create VMs without GPU passthrough
  ESXI_PASSWORD=secret ./provision-vms.sh

  # Create VMs with GPU passthrough
  ESXI_PASSWORD=secret GPU_PASSTHRU_ID=0:66:0.0 ./provision-vms.sh

  # Add GPU to existing VM
  ESXI_PASSWORD=secret GPU_PASSTHRU_ID=0:66:0.0 ./provision-vms.sh --add-gpu k3s-gpu-agent

  # Destroy VMs
  ESXI_PASSWORD=secret ./provision-vms.sh --destroy
EOF
}

# Main
case "${1:-}" in
    --destroy)
        check_prereqs
        destroy_vms
        ;;
    --add-gpu)
        if [[ -z "${2:-}" ]]; then
            log_error "Usage: ./provision-vms.sh --add-gpu <vm-name>"
            exit 1
        fi
        if [[ -z "${GPU_PASSTHRU_ID}" ]]; then
            log_error "GPU_PASSTHRU_ID is required"
            log_error "Example: GPU_PASSTHRU_ID=0:66:0.0 ./provision-vms.sh --add-gpu k3s-gpu-agent"
            exit 1
        fi
        check_prereqs
        vm_name="$2"
        vmid=$(get_vm_id "${vm_name}")
        if [[ -z "$vmid" ]]; then
            log_error "VM '${vm_name}' not found"
            exit 1
        fi
        power_off_vm "${vmid}"
        add_gpu_passthrough "${vmid}" "${vm_name}" "${GPU_PASSTHRU_ID}"
        log_info "GPU passthrough added. Power on VM manually when ready."
        ;;
    --help|-h)
        show_help
        ;;
    *)
        provision_vms
        ;;
esac
