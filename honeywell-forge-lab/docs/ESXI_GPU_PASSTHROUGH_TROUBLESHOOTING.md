# ESXi GPU Passthrough Troubleshooting Guide

## Overview

This document covers the troubleshooting steps for Tesla P40 GPU passthrough on ESXi to K3s VM for the Honeywell airgapped deployment.

## Environment

| Component | Details |
|-----------|---------|
| ESXi Host | 192.168.1.144 |
| Jump Host (ocp-svc) | 192.168.1.238 |
| K3s Server | 192.168.22.98 |
| K3s GPU Agent | 192.168.22.82 |
| GPU | NVIDIA Tesla P40 (24GB VRAM) |
| VM OS | Ubuntu 20.04 LTS |
| Driver Version | 535.230.02 |

## Current Status

**Issue**: GPU is visible in VM via `lspci` but `nvidia-smi` returns "No devices were found"

**Error in dmesg**:
```
NVRM: GPU 0000:05:00.0: RmInitAdapter failed! (0x24:0x72:1447)
NVRM: GPU 0000:05:00.0: rm_init_adapter failed, device minor number 0
caller os_map_kernel_space.part.0+0xa2/0xb0 [nvidia] mapping multiple BARs
```

## VMX Settings Applied

The following settings have been added to `/vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx`:

```vmx
# PCI Passthrough configuration
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"
pciPassthru0.deviceId = "0x1b38"
pciPassthru0.vendorId = "0x10de"

# 64-bit MMIO for large BAR GPUs (Tesla P40 has 32GB BAR1)
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"

# Hide hypervisor from guest (required for NVIDIA drivers)
hypervisor.cpuid.v0 = "FALSE"

# Disable SVGA to avoid conflicts with GPU passthrough
svga.present = "FALSE"

# Memory settings (must be reserved for passthrough)
sched.mem.min = "16384"
sched.mem.minSize = "16384"
sched.mem.pin = "TRUE"
```

## Steps Completed

### 1. GPU Passthrough Enabled in ESXi
- GPU marked for passthrough in: ESXi > Host > Configure > Hardware > PCI Devices
- Tesla P40 device ID: 0x1b38, vendor ID: 0x10de

### 2. VM Configuration
- VM hardware version: vmx-21
- Memory: 16GB (all reserved/pinned)
- GPU added as PCI passthrough device

### 3. VMX Parameters Added
Via ESXi shell commands:
```bash
# Power off VM first
vim-cmd vmsvc/power.off <VMID>

# Add 64-bit MMIO support
cat >> /vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx << 'EOF'
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"
hypervisor.cpuid.v0 = "FALSE"
svga.present = "FALSE"
EOF

# Reload and power on
vim-cmd vmsvc/reload <VMID>
vim-cmd vmsvc/power.on <VMID>
```

### 4. NVIDIA Driver Installation (on GPU VM)
Driver installed directly on host due to airgapped environment:
```bash
# Downloaded on ocp-svc (has internet)
wget https://us.download.nvidia.com/tesla/535.230.02/NVIDIA-Linux-x86_64-535.230.02.run

# Copied to GPU agent
scp NVIDIA-Linux-x86_64-535.230.02.run dare@192.168.22.82:/tmp/

# Installed on GPU agent
sudo bash /tmp/NVIDIA-Linux-x86_64-535.230.02.run --silent --no-questions --dkms
```

## Remaining Issue: BAR Mapping

The `RmInitAdapter failed! (0x24:0x72:1447)` error with "mapping multiple BARs" indicates the GPU's Base Address Registers (BARs) are not being properly mapped by ESXi.

### ESXi vmware.log shows:
```
PCIPassthru: Device 0000:42:00.0 barIndex 0 type 2 realaddr 0xd4000000 size 16777216 flags 0
PCIPassthru: Device 0000:42:00.0 barIndex 1 type 3 realaddr 0x3b800000000 size 34359738368 flags 12
PCIPassthru: Device 0000:42:00.0 barIndex 3 type 3 realaddr 0x3b7fe000000 size 33554432 flags 12
```

- BAR0: 16MB (control registers)
- BAR1: 32GB (GPU memory aperture) - This is the large BAR
- BAR3: 32MB (additional registers)

## Next Steps to Try

### 1. ESXi Host Reboot (RECOMMENDED)
The most likely fix. GPU passthrough often requires an ESXi host reboot after enabling passthrough to properly release the GPU from ESXi's direct control.

```bash
# On ESXi host
# First power off all VMs
vim-cmd vmsvc/getallvms
vim-cmd vmsvc/power.off <each-vmid>

# Reboot ESXi
reboot
```

### 2. Check ESXi Passthrough Status
After reboot, verify GPU is properly in passthrough mode:
```bash
esxcli hardware pci pcipassthru list | grep -i nvidia
```

### 3. Alternative: Try EFI Boot
If VM is using BIOS boot, try switching to EFI:
```vmx
firmware = "efi"
```

### 4. Alternative: Reduce MMIO Size
Some systems work better with smaller MMIO allocation:
```vmx
pciPassthru.64bitMMIOSizeGB = "64"
```

### 5. Check for IOMMU/VT-d Issues
On ESXi host:
```bash
esxcli system settings kernel list | grep -i iommu
vmkload_mod -l | grep -i vmd
```

## Useful Commands

### ESXi Commands
```bash
# List all VMs
vim-cmd vmsvc/getallvms

# Power on/off VM
vim-cmd vmsvc/power.on <VMID>
vim-cmd vmsvc/power.off <VMID>

# Reload VM config
vim-cmd vmsvc/reload <VMID>

# Check VM power state
vim-cmd vmsvc/get.summary <VMID> | grep powerState

# View VM log
tail -100 /vmfs/volumes/datastore1/<vm-name>/vmware.log

# List passthrough devices
esxcli hardware pci pcipassthru list
```

### Guest VM Commands (from ocp-svc)
```bash
# SSH to GPU agent
sshpass -p 'Andrea24!!' ssh dare@192.168.22.82

# Check GPU visibility
lspci | grep -i nvidia

# Check driver status
nvidia-smi

# Check kernel messages
dmesg | grep -i nvidia

# Check nvidia modules
lsmod | grep nvidia
```

## References

- [VMware KB: Configuring PCI/PCIe Passthrough](https://kb.vmware.com/s/article/1010789)
- [NVIDIA Virtual GPU Documentation](https://docs.nvidia.com/grid/)
- [ESXi GPU Passthrough for Tesla](https://docs.nvidia.com/datacenter/tesla/tesla-installation-notes/)

## Document History

| Date | Change |
|------|--------|
| 2024-12-10 | Initial documentation of troubleshooting steps |
