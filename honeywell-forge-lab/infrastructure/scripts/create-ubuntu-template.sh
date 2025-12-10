#!/bin/bash
# =============================================================================
# Create Ubuntu VM Template on ESXi via CLI
# =============================================================================
#
# This script creates a VM on ESXi that can be used as a template.
# Run the commands FROM the ESXi host (SSH into ESXi first).
#
# IMPORTANT: For GPU passthrough with large BAR GPUs (Tesla P40, etc.):
#   - GPU VMs MUST use EFI firmware for proper 64-bit BAR mapping
#   - BIOS firmware cannot allocate 64-bit address space for BARs >4GB
#   - Use the EFI template instructions below for GPU agent VMs
#
# Prerequisites:
#   - Ubuntu ISO on datastore (e.g., ubuntu-20.04.6-live-server-amd64.iso)
#   - ESXi SSH access
#
# =============================================================================

# Configuration - adjust these as needed
VM_NAME="ubuntu-template"
DATASTORE="datastore1"
DATASTORE_PATH="/vmfs/volumes/${DATASTORE}"
ISO_FILE="ubuntu-20.04.6-live-server-amd64.iso"
ISO_PATH="${DATASTORE_PATH}/${ISO_FILE}"
VM_DIR="${DATASTORE_PATH}/${VM_NAME}"
VMX_FILE="${VM_DIR}/${VM_NAME}.vmx"
VMDK_FILE="${VM_DIR}/${VM_NAME}.vmdk"

# VM Specs
VM_CPUS=2
VM_MEMORY_MB=4096
VM_DISK_GB=50

cat << 'INSTRUCTIONS'
=============================================================================
Ubuntu Template Creation - Manual Steps
=============================================================================

Run these commands on your ESXi host (ssh root@192.168.1.144):

=============================================================================
OPTION A: BIOS Template (for K3s Server - no GPU)
=============================================================================

# -----------------------------------------------------------------------------
# STEP 1A: Create VM directory and virtual disk (BIOS)
# -----------------------------------------------------------------------------

VM_NAME="ubuntu-template"
VM_DIR="/vmfs/volumes/datastore1/${VM_NAME}"
mkdir -p "${VM_DIR}"
vmkfstools -c 50G -d thin "${VM_DIR}/${VM_NAME}.vmdk"

# -----------------------------------------------------------------------------
# STEP 2A: Create VMX configuration file (BIOS)
# -----------------------------------------------------------------------------

cat > "${VM_DIR}/${VM_NAME}.vmx" << 'EOF'
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
displayName = "ubuntu-template"
guestOS = "ubuntu-64"
memSize = "4096"
numvcpus = "2"
scsi0.virtualDev = "lsilogic"
scsi0.present = "TRUE"
scsi0:0.fileName = "ubuntu-template.vmdk"
scsi0:0.present = "TRUE"
sata0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "/vmfs/volumes/datastore1/ubuntu-20.04.6-live-server-amd64.iso"
sata0:0.present = "TRUE"
sata0:0.startConnected = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "VM Network"
ethernet0.addressType = "generated"
ethernet0.present = "TRUE"
bios.bootOrder = "cdrom,hdd"
RemoteDisplay.vnc.enabled = "TRUE"
RemoteDisplay.vnc.port = "5901"
EOF

=============================================================================
OPTION B: EFI Template (REQUIRED for GPU Agent with large BAR GPUs)
=============================================================================
#
# IMPORTANT: Use EFI for GPU VMs!
# - Tesla P40 has 32GB BAR1 which requires 64-bit address space
# - BIOS firmware cannot allocate >4GB BARs properly
# - EFI firmware correctly maps large GPU memory regions
#

# -----------------------------------------------------------------------------
# STEP 1B: Create VM directory and virtual disk (EFI)
# -----------------------------------------------------------------------------

VM_NAME="ubuntu-efi-template"
VM_DIR="/vmfs/volumes/datastore1/${VM_NAME}"
mkdir -p "${VM_DIR}"
vmkfstools -c 50G -d thin "${VM_DIR}/${VM_NAME}.vmdk"

# -----------------------------------------------------------------------------
# STEP 2B: Create VMX configuration file (EFI + GPU ready)
# -----------------------------------------------------------------------------

cat > "${VM_DIR}/${VM_NAME}.vmx" << 'EOF'
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "ubuntu-efi-template"
guestOS = "ubuntu-64"
firmware = "efi"
memSize = "4096"
numvcpus = "2"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "ubuntu-efi-template.vmdk"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.deviceType = "cdrom-image"
sata0:0.fileName = "/vmfs/volumes/datastore1/ubuntu-20.04.6-live-server-amd64.iso"
sata0:0.startConnected = "TRUE"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "VM Network"
ethernet0.addressType = "generated"
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"
hypervisor.cpuid.v0 = "FALSE"
tools.syncTime = "TRUE"
RemoteDisplay.vnc.enabled = "TRUE"
RemoteDisplay.vnc.port = "5901"
EOF

=============================================================================
Common Steps (for both BIOS and EFI)
=============================================================================

# -----------------------------------------------------------------------------
# STEP 3: Register and power on VM
# -----------------------------------------------------------------------------

VMID=$(vim-cmd solo/registervm "${VM_DIR}/${VM_NAME}.vmx")
echo "VM registered with ID: ${VMID}"
vim-cmd vmsvc/power.on ${VMID}

# -----------------------------------------------------------------------------
# STEP 4: Install Ubuntu
# -----------------------------------------------------------------------------
# Access console via:
#   - ESXi Web UI: https://192.168.1.144 -> VM -> Console
#   - VNC: Connect to 192.168.1.144:5901
#
# During Ubuntu installation:
#   - Choose minimal install
#   - Create user (e.g., 'dare')
#   - Enable OpenSSH Server
#   - Use entire disk

# -----------------------------------------------------------------------------
# STEP 5: After Ubuntu install, disconnect ISO and reboot
# -----------------------------------------------------------------------------

vim-cmd vmsvc/power.off ${VMID}
sed -i 's/sata0:0.startConnected = "TRUE"/sata0:0.startConnected = "FALSE"/' "${VM_DIR}/${VM_NAME}.vmx"
vim-cmd vmsvc/power.on ${VMID}

# -----------------------------------------------------------------------------
# STEP 6: SSH to Ubuntu VM and prepare for templating
# -----------------------------------------------------------------------------
# Find the VM IP:
#   vim-cmd vmsvc/get.guest ${VMID} | grep -i ipaddress
#
# Then SSH in (from ocp-svc-vm or directly if on same network):
#   ssh <username>@<IP_ADDRESS>

# Run these commands on the Ubuntu VM:
sudo apt update
sudo apt install -y cloud-init open-vm-tools
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo cloud-init clean
sudo rm -f /etc/ssh/ssh_host_*
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
history -c
cat /dev/null > ~/.bash_history
sudo shutdown -h now

# -----------------------------------------------------------------------------
# STEP 7: Template is ready!
# -----------------------------------------------------------------------------
# The VM "ubuntu-template" can now be cloned by Terraform.
# Verify it's powered off:
#   vim-cmd vmsvc/power.getstate ${VMID}

=============================================================================
Template Details (as created):
=============================================================================
  VM Name:        ubuntu-template
  VM ID:          121
  OS:             Ubuntu 20.04.6 LTS
  Default User:   dare
  CPUs:           2
  Memory:         4 GB
  Disk:           50 GB
  Cloud-init:     Installed & cleaned
  VMware Tools:   Installed (open-vm-tools)
=============================================================================
INSTRUCTIONS
