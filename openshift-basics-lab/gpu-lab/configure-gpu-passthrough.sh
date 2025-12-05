#!/bin/bash
#
# ESXi GPU Passthrough Configuration Script
# ==========================================
# This script configures GPU passthrough for a VM on ESXi 8.0.2
#
# Usage: ./configure-gpu-passthrough.sh <VM_NAME> <PCI_ADDRESS_HEX>
# Example: ./configure-gpu-passthrough.sh ocp-w-1 0000:42:00.0
#
# Prerequisites:
# - SSH access to ESXi host (set ESXI_HOST variable or use -h flag)
# - GPU passthrough already enabled in ESXi (esxcli hardware pci pcipassthru set -d <addr> -e true)
# - ESXi rebooted after enabling passthrough
# - "Above 4G Decoding" enabled in server BIOS
#

set -e

# Configuration
ESXI_HOST="${ESXI_HOST:-192.168.1.200}"
ESXI_USER="${ESXI_USER:-root}"
DATASTORE="${DATASTORE:-datastore1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <VM_NAME> <PCI_ADDRESS_HEX>

Configure GPU passthrough for a VM on ESXi 8.0.2

Arguments:
  VM_NAME           Name of the VM (e.g., ocp-w-1)
  PCI_ADDRESS_HEX   GPU PCI address in hex format (e.g., 0000:42:00.0)

Options:
  -h, --host HOST   ESXi host IP/hostname (default: \$ESXI_HOST or 192.168.1.200)
  -u, --user USER   ESXi SSH user (default: \$ESXI_USER or root)
  -d, --datastore   Datastore name (default: \$DATASTORE or datastore1)
  -m, --memory MB   VM memory size in MB (auto-detected if not specified)
  --dry-run         Show what would be done without making changes
  --help            Show this help message

Environment Variables:
  ESXI_HOST         ESXi host IP/hostname
  ESXI_USER         ESXi SSH username
  DATASTORE         ESXi datastore name

Examples:
  $0 ocp-w-1 0000:42:00.0
  $0 -h 192.168.1.200 -m 16384 ocp-w-1 0000:42:00.0
  ESXI_HOST=esxi.local $0 ocp-w-1 0000:42:00.0

EOF
    exit 1
}

# Parse arguments
DRY_RUN=false
VM_MEMORY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            ESXI_HOST="$2"
            shift 2
            ;;
        -u|--user)
            ESXI_USER="$2"
            shift 2
            ;;
        -d|--datastore)
            DATASTORE="$2"
            shift 2
            ;;
        -m|--memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 2 ]]; then
    log_error "Missing required arguments"
    usage
fi

VM_NAME="$1"
PCI_ADDR_HEX="$2"

# Validate PCI address format
if [[ ! "$PCI_ADDR_HEX" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]$ ]]; then
    log_error "Invalid PCI address format: $PCI_ADDR_HEX"
    log_error "Expected format: SSSS:BB:DD.F (e.g., 0000:42:00.0)"
    exit 1
fi

# Convert hex bus number to decimal
# Extract bus number (e.g., "42" from "0000:42:00.0")
BUS_HEX=$(echo "$PCI_ADDR_HEX" | cut -d: -f2)
BUS_DEC=$((16#$BUS_HEX))

# Extract other parts
SEGMENT=$(echo "$PCI_ADDR_HEX" | cut -d: -f1)
DEVICE=$(echo "$PCI_ADDR_HEX" | cut -d: -f3 | cut -d. -f1)
FUNCTION=$(echo "$PCI_ADDR_HEX" | cut -d. -f2)

# Convert segment to decimal (usually 0)
SEGMENT_DEC=$((16#$SEGMENT))

# Build decimal format for VMX (S:B:D.F with decimal B)
PCI_ADDR_DEC="${SEGMENT_DEC}:${BUS_DEC}:$((16#$DEVICE)).${FUNCTION}"

log_info "VM Name: $VM_NAME"
log_info "ESXi Host: $ESXI_HOST"
log_info "PCI Address (hex): $PCI_ADDR_HEX"
log_info "PCI Address (decimal for VMX): $PCI_ADDR_DEC"
log_info ""

# SSH command helper
ssh_esxi() {
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${ESXI_USER}@${ESXI_HOST}" "$@"
}

# Test SSH connection
log_info "Testing SSH connection to ESXi..."
if ! ssh_esxi "echo 'SSH OK'" &>/dev/null; then
    log_error "Cannot connect to ESXi host: $ESXI_HOST"
    log_error "Ensure SSH is enabled and credentials are correct"
    exit 1
fi
log_info "SSH connection successful"

# Get VM ID
log_info "Finding VM ID for '$VM_NAME'..."
VM_INFO=$(ssh_esxi "vim-cmd vmsvc/getallvms | grep -w '$VM_NAME'")
if [[ -z "$VM_INFO" ]]; then
    log_error "VM not found: $VM_NAME"
    exit 1
fi
VMID=$(echo "$VM_INFO" | awk '{print $1}')
log_info "VM ID: $VMID"

# Get VMX path
VMX_PATH="/vmfs/volumes/${DATASTORE}/${VM_NAME}/${VM_NAME}.vmx"
log_info "VMX Path: $VMX_PATH"

# Verify VMX exists
if ! ssh_esxi "test -f '$VMX_PATH'"; then
    log_error "VMX file not found: $VMX_PATH"
    exit 1
fi

# Get GPU device info
log_info "Getting GPU device information..."
GPU_INFO=$(ssh_esxi "esxcli hardware pci list | grep -A20 '$PCI_ADDR_HEX'")
if [[ -z "$GPU_INFO" ]]; then
    log_error "GPU not found at PCI address: $PCI_ADDR_HEX"
    exit 1
fi

VENDOR_ID=$(echo "$GPU_INFO" | grep "Vendor ID:" | awk '{print $3}')
DEVICE_ID=$(echo "$GPU_INFO" | grep "Device ID:" | head -1 | awk '{print $3}')
SUBVENDOR_ID=$(echo "$GPU_INFO" | grep "SubVendor ID:" | awk '{print $3}')
SUBDEVICE_ID=$(echo "$GPU_INFO" | grep "SubDevice ID:" | awk '{print $3}')
DEVICE_CLASS=$(echo "$GPU_INFO" | grep "Device Class:" | head -1 | awk '{print $3}')
DEVICE_NAME=$(echo "$GPU_INFO" | grep "Device Name:" | cut -d: -f2- | xargs)

log_info "GPU: $DEVICE_NAME"
log_info "Vendor ID: $VENDOR_ID, Device ID: $DEVICE_ID"
log_info "SubVendor: $SUBVENDOR_ID, SubDevice: $SUBDEVICE_ID"

# Check passthrough status
PASSTHRU_STATUS=$(ssh_esxi "esxcli hardware pci pcipassthru list | grep '$PCI_ADDR_HEX'" | awk '{print $2}')
if [[ "$PASSTHRU_STATUS" != "true" ]]; then
    log_error "GPU passthrough is not enabled for $PCI_ADDR_HEX"
    log_error "Run: esxcli hardware pci pcipassthru set -d $PCI_ADDR_HEX -e true"
    log_error "Then reboot ESXi"
    exit 1
fi

# Verify GPU is in passthru mode (not claimed by vmkernel)
GPU_OWNER=$(ssh_esxi "vmkchdev -l | grep '$PCI_ADDR_HEX'" | awk '{print $4}')
if [[ "$GPU_OWNER" != "passthru" ]]; then
    log_error "GPU is owned by '$GPU_OWNER' instead of 'passthru'"
    log_error "ESXi reboot may be required after enabling passthrough"
    exit 1
fi
log_info "GPU passthrough status: Enabled and active"

# Get ESXi system UUID
SYSTEM_UUID=$(ssh_esxi "esxcli system uuid get")
log_info "ESXi System UUID: $SYSTEM_UUID"

# Get VM memory size if not specified
if [[ -z "$VM_MEMORY" ]]; then
    VM_MEMORY=$(ssh_esxi "grep '^memSize' '$VMX_PATH'" | cut -d'"' -f2)
    log_info "VM Memory (auto-detected): ${VM_MEMORY} MB"
else
    log_info "VM Memory (specified): ${VM_MEMORY} MB"
fi

# Check VM power state
VM_STATE=$(ssh_esxi "vim-cmd vmsvc/power.getstate $VMID | tail -1")
log_info "VM Power State: $VM_STATE"

if [[ "$VM_STATE" != "Powered off" ]]; then
    log_warn "VM is not powered off. GPU passthrough configuration requires the VM to be off."
    log_warn "Please power off the VM first, or use --force to attempt anyway"
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Power off VM now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Powering off VM..."
            ssh_esxi "vim-cmd vmsvc/power.off $VMID"
            sleep 5
        else
            exit 1
        fi
    fi
fi

# Generate VMX configuration
VMX_CONFIG="
# GPU Passthrough Configuration - Added by configure-gpu-passthrough.sh
# GPU: $DEVICE_NAME
# PCI Address: $PCI_ADDR_HEX -> $PCI_ADDR_DEC (VMX format)
# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

# Memory reservation (required for GPU passthrough)
sched.mem.min = \"$VM_MEMORY\"
sched.mem.minSize = \"$VM_MEMORY\"
sched.mem.pin = \"TRUE\"

# PCI Passthrough device configuration
pciPassthru0.present = \"TRUE\"
pciPassthru0.id = \"$PCI_ADDR_DEC\"
pciPassthru0.deviceId = \"$DEVICE_ID\"
pciPassthru0.vendorId = \"$VENDOR_ID\"
pciPassthru0.systemId = \"$SYSTEM_UUID\"
pciPassthru0.class = \"$DEVICE_CLASS\"
pciPassthru0.subDeviceId = \"$SUBDEVICE_ID\"
pciPassthru0.subVendorId = \"$SUBVENDOR_ID\"
pciPassthru.use64bitMMIO = \"TRUE\"
pciPassthru.64bitMMIOSizeGB = \"64\"
"

echo ""
log_info "Generated VMX configuration:"
echo "----------------------------------------"
echo "$VMX_CONFIG"
echo "----------------------------------------"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN - No changes made"
    exit 0
fi

# Backup existing VMX
BACKUP_NAME="${VM_NAME}.vmx.backup.$(date +%Y%m%d%H%M%S)"
log_info "Creating backup: $BACKUP_NAME"
ssh_esxi "cp '$VMX_PATH' '/vmfs/volumes/${DATASTORE}/${VM_NAME}/${BACKUP_NAME}'"

# Remove any existing passthrough configuration
log_info "Removing existing passthrough configuration..."
ssh_esxi "sed -i '/pciPassthru/d' '$VMX_PATH'"
ssh_esxi "sed -i '/sched.mem.min/d' '$VMX_PATH'"
ssh_esxi "sed -i '/sched.mem.minSize/d' '$VMX_PATH'"
ssh_esxi "sed -i '/sched.mem.pin/d' '$VMX_PATH'"

# Add new configuration
log_info "Adding GPU passthrough configuration..."
ssh_esxi "cat >> '$VMX_PATH'" << EOF
$VMX_CONFIG
EOF

# Reload VM configuration
log_info "Reloading VM configuration..."
ssh_esxi "vim-cmd vmsvc/reload $VMID"

# Power on VM
log_info "Powering on VM..."
POWER_ON_RESULT=$(ssh_esxi "vim-cmd vmsvc/power.on $VMID" 2>&1)

if echo "$POWER_ON_RESULT" | grep -q "Power on failed"; then
    log_error "Failed to power on VM:"
    echo "$POWER_ON_RESULT"
    log_error ""
    log_error "Check vmware.log for details:"
    log_error "  tail -50 /vmfs/volumes/${DATASTORE}/${VM_NAME}/vmware.log"
    exit 1
fi

# Verify power state
sleep 3
VM_STATE=$(ssh_esxi "vim-cmd vmsvc/power.getstate $VMID | tail -1")
if [[ "$VM_STATE" == "Powered on" ]]; then
    log_info "VM powered on successfully!"
    log_info ""
    log_info "GPU passthrough configuration complete."
    log_info ""
    log_info "Next steps:"
    log_info "  1. Wait for VM to boot"
    log_info "  2. SSH into VM and verify GPU: lspci | grep -i nvidia"
    log_info "  3. If this is an OpenShift node, uncordon it:"
    log_info "     oc adm uncordon ${VM_NAME}.lab.ocp.lan"
else
    log_error "VM did not power on. Current state: $VM_STATE"
    exit 1
fi
