# ESXi 8.0.2 GPU Passthrough to OpenShift VM Guide

This guide documents the complete process to configure GPU passthrough from ESXi 8.0.2 to an OpenShift worker node VM. This was tested with a Tesla P40 GPU.

## Prerequisites

- ESXi 8.0.2 host
- Server BIOS with VT-d/IOMMU enabled
- Server BIOS with "Above 4G Decoding" / "Memory Mapped I/O above 4GB" enabled (required for GPUs with >4GB VRAM)
- OpenShift cluster with worker nodes running as VMs

## Hardware Configuration Used

- **GPU**: NVIDIA Tesla P40 (24GB VRAM)
- **PCI Address**: `0000:42:00.0` (hex) = `0:66:0.0` (decimal format for VMX)
- **Vendor ID**: `0x10de` (NVIDIA)
- **Device ID**: `0x1b38` (Tesla P40)
- **Subsystem Vendor ID**: `0x10de`
- **Subsystem Device ID**: `0x11d9`

## Step 1: BIOS Configuration

Before starting, ensure these BIOS settings are enabled:

1. **VT-d / IOMMU** - Required for device passthrough
2. **Above 4G Decoding** - Required for GPUs with >4GB VRAM (Tesla P40 has 24GB)
3. **SR-IOV** (optional) - For future vGPU support

## Step 2: Identify GPU PCI Address

SSH into ESXi host and identify the GPU:

```bash
# List all PCI devices and find NVIDIA GPU
lspci | grep -i nvidia

# Output example:
# 0000:42:00.0 3D controller: NVIDIA Corporation GP102GL [Tesla P40]
```

**Important**: Note the PCI address format `SSSS:BB:DD.F` (Segment:Bus:Device.Function)
- Segment: `0000`
- Bus: `42` (hex) = `66` (decimal)
- Device: `00`
- Function: `0`

## Step 3: Enable GPU Passthrough in ESXi

```bash
# Enable passthrough for the GPU device
esxcli hardware pci pcipassthru set -d 0000:42:00.0 -e true

# Disable Interrupt Remapping (required for some GPUs)
esxcli system settings kernel set -s iovDisableIR -v TRUE

# Disable ACS Check (may be required)
esxcli system settings kernel set -s disableACSCheck -v TRUE

# Verify passthrough is enabled
esxcli hardware pci pcipassthru list | grep 42:00
# Should show: 0000:42:00.0     true
```

## Step 4: Reboot ESXi Host

```bash
# Reboot is required after enabling passthrough
reboot
```

After reboot, verify the GPU is in passthrough mode:

```bash
# Check device ownership - should show "passthru" not "vmkernel"
vmkchdev -l | grep 42:00
# Output: 0000:42:00.0 10de:1b38 10de:11d9 passthru

# Verify passthrough status
esxcli hardware pci list | grep -A10 "0000:42:00.0"
# Should show:
#   Configured Owner: VM Passthru
#   Current Owner: VM Passthru
```

## Step 5: Prepare the VM

Before adding GPU passthrough, the VM must be properly prepared:

### 5.1 Drain the OpenShift Node (if running)

```bash
# From a machine with oc access
oc adm drain ocp-w-1.lab.ocp.lan --ignore-daemonsets --delete-emptydir-data --disable-eviction
```

### 5.2 Power Off the VM

```bash
# On ESXi host
vim-cmd vmsvc/power.off <VMID>

# Find VMID with:
vim-cmd vmsvc/getallvms | grep ocp-w-1
```

## Step 6: Configure VMX File for GPU Passthrough

This is the critical step. ESXi 8.0.2 with VM hardware version 21 requires a specific PCI address format.

### 6.1 Get ESXi System UUID

```bash
esxcli system uuid get
# Example output: 65106d9a-406e-5fda-b7ab-b8ca3a63b8b4
```

### 6.2 Convert PCI Address to Decimal Format

**CRITICAL**: ESXi 8 hardware version 21 requires the bus number in DECIMAL without leading zeros:

| Hex Address | Decimal Format (VMX) |
|-------------|---------------------|
| `0000:42:00.0` | `0:66:0.0` |
| `0000:3b:00.0` | `0:59:0.0` |
| `0000:86:00.0` | `0:134:0.0` |

Conversion: `0x42` = `66` decimal

### 6.3 Add Passthrough Configuration to VMX

```bash
# Backup VMX file first
cp /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx.backup

# Add GPU passthrough configuration
cat >> /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx << 'EOF'
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"
pciPassthru0.deviceId = "0x1b38"
pciPassthru0.vendorId = "0x10de"
pciPassthru0.systemId = "65106d9a-406e-5fda-b7ab-b8ca3a63b8b4"
pciPassthru0.class = "0x0302"
pciPassthru0.subDeviceId = "0x11d9"
pciPassthru0.subVendorId = "0x10de"
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "64"
EOF
```

### 6.4 Configure Memory Reservation

GPU passthrough requires full memory reservation:

```bash
# Check current memory size
grep "^memSize" /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx
# Example: memSize = "16384"

# Add/update memory reservation settings
# These should match the VM's memSize value
cat >> /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx << 'EOF'
sched.mem.min = "16384"
sched.mem.minSize = "16384"
sched.mem.pin = "TRUE"
EOF
```

**Note**: Ensure there are no duplicate entries. Check with:
```bash
grep -E "sched.mem|pciPassthru" /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx
```

## Step 7: Power On the VM

```bash
# Reload VM configuration
vim-cmd vmsvc/reload <VMID>

# Power on
vim-cmd vmsvc/power.on <VMID>

# Verify power state
vim-cmd vmsvc/power.getstate <VMID>
# Should show: Powered on
```

## Step 8: Verify GPU in VM

Once the VM is running, verify the GPU is visible:

```bash
# SSH into the OpenShift worker node
ssh core@ocp-w-1.lab.ocp.lan

# Check for NVIDIA GPU
lspci | grep -i nvidia
# Should show: 00:0e.0 3D controller: NVIDIA Corporation GP102GL [Tesla P40]

# Check dmesg for GPU initialization
dmesg | grep -i nvidia
```

## Step 9: Uncordon the OpenShift Node

```bash
# From a machine with oc access
oc adm uncordon ocp-w-1.lab.ocp.lan

# Verify node is Ready
oc get nodes
```

## Troubleshooting

### Error: "Module 'DevicePowerOn' power on failed"

Check vmware.log for specific errors:
```bash
tail -100 /vmfs/volumes/datastore1/<vm-name>/vmware.log | grep -iE 'error|fail|pci|passthru'
```

Common causes:
1. **"total number of pages needed exceeds limit"** - Add memory reservation and 64-bit MMIO settings
2. **"Failed to find a suitable device"** - Wrong PCI address format (use decimal bus number)
3. **"Failed to generate predicates"** - Missing or incorrect device IDs
4. **"Variable already defined"** - Duplicate entries in VMX file

### Error: "AH Failed to find a suitable device for pciPassthru0"

This usually means the PCI address format is wrong. ESXi 8.0.2 with HW version 21 requires:
- Decimal bus number (not hex)
- Format: `S:B:D.F` where B is decimal

Wrong: `pciPassthru0.id = "0000:42:00.0"`
Correct: `pciPassthru0.id = "0:66:0.0"`

### Error: "Failed to add BAR memory" / "Limit exceeded"

Enable "Above 4G Decoding" in server BIOS. This is required for GPUs with >4GB VRAM.

### GPU shows "vmkernel" instead of "passthru"

```bash
# Check current owner
vmkchdev -l | grep <pci-address>

# If shows vmkernel, reboot ESXi after enabling passthrough
esxcli hardware pci pcipassthru set -d <pci-address> -e true
reboot
```

### VM goes to "invalid" state

The VMX file has syntax errors or duplicate entries. Restore from backup:
```bash
cp /vmfs/volumes/datastore1/<vm>/vmx.backup /vmfs/volumes/datastore1/<vm>/<vm>.vmx
vim-cmd vmsvc/reload <VMID>
```

## VMX Configuration Reference

Complete working VMX passthrough configuration for Tesla P40:

```
# Memory reservation (required for passthrough)
sched.mem.min = "16384"
sched.mem.minSize = "16384"
sched.mem.pin = "TRUE"

# GPU Passthrough configuration
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"
pciPassthru0.deviceId = "0x1b38"
pciPassthru0.vendorId = "0x10de"
pciPassthru0.systemId = "<esxi-system-uuid>"
pciPassthru0.class = "0x0302"
pciPassthru0.subDeviceId = "0x11d9"
pciPassthru0.subVendorId = "0x10de"
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "64"
```

## Next Steps

After GPU passthrough is working:
1. Install NVIDIA GPU Operator on OpenShift
2. Verify GPU is detected by the operator
3. Deploy GPU workloads

See: [GPU Operator Installation Guide](./GPU_OPERATOR_INSTALLATION.md)
