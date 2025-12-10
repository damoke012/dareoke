# ESXi GPU Passthrough Troubleshooting Guide

## Overview

This document covers the troubleshooting steps for Tesla P40 GPU passthrough on ESXi to K3s VM for the Honeywell airgapped deployment.

## Environment

| Component | Details |
|-----------|---------|
| Physical Server | Dell PowerEdge R720xd |
| ESXi Host | 192.168.1.144 |
| Jump Host (ocp-svc) | 192.168.1.238 |
| K3s Server | 192.168.22.98 |
| K3s GPU Agent | 192.168.22.82 (also 192.168.1.229 on secondary NIC) |
| GPU | NVIDIA Tesla P40 (24GB VRAM) |
| VM OS | Ubuntu 20.04 LTS |
| Driver Version | 535.230.02 |

## Quick Reference - VM IDs

| VM Name | VMID |
|---------|------|
| ocp-svc-vm | 84 |
| k3s-server | 122 |
| k3s-gpu-agent | 125 |

---

## BIOS Settings Required (Dell PowerEdge R720xd)

Access via: Dell Lifecycle Controller → System Setup → System BIOS

### Processor Settings
| Setting | Required Value |
|---------|----------------|
| Virtualization Technology | **Enabled** |
| Logical Processor | Enabled |

### Integrated Devices
| Setting | Required Value |
|---------|----------------|
| SR-IOV Global Enable | **Enabled** |
| Memory Mapped I/O above 4GB | **Enabled** |
| Embedded Video Controller | Enabled |

---

## VMX Settings for GPU Passthrough

File: `/vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx`

```vmx
# PCI Passthrough configuration
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"
pciPassthru0.deviceId = "0x1b38"
pciPassthru0.vendorId = "0x10de"
pciPassthru0.systemId = "65106d9a-406e-5fda-b7ab-b8ca3a63b8b4"
pciPassthru0.class = "0x0302"
pciPassthru0.subDeviceId = "0x11d9"
pciPassthru0.subVendorId = "0x10de"
pciPassthru0.pciSlotNumber = "2208"

# 64-bit MMIO for large BAR GPUs (Tesla P40 has 32GB BAR1)
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"

# Hide hypervisor from guest (required for NVIDIA drivers)
hypervisor.cpuid.v0 = "FALSE"

# Additional passthrough settings
pciPassthru0.msiEnabled = "TRUE"
pciPassthru0.cfg.enable_bar_mapping = "TRUE"
pciPassthru.allowP2P = "TRUE"
pciPassthru.RelaxACSCheck = "TRUE"

# Memory settings (must be reserved for passthrough)
sched.mem.min = "16384"
sched.mem.minSize = "16384"
sched.mem.pin = "TRUE"
```

---

## Known Issue: BAR1 Unassigned

### Symptom
```bash
$ lspci -vvv -s 05:00.0 | grep Region
Region 0: Memory at fc000000 (32-bit, non-prefetchable) [size=16M]
Region 1: Memory at <unassigned> (64-bit, prefetchable)    # <-- PROBLEM
Region 3: Memory at e4000000 (64-bit, prefetchable) [size=32M]
```

### Error Messages
```
NVRM: This PCI I/O region assigned to your NVIDIA device is invalid:
      NVRM: BAR1 is 0M @ 0x0 (PCI:0000:05:00.0)
NVRM: GPU 0000:05:00.0: RmInitAdapter failed! (0x24:0x72:1447)
```

### Root Cause
The Tesla P40's 32GB BAR1 (GPU memory aperture) is not being mapped by the VM's BIOS. ESXi correctly passes the BAR (seen in vmware.log) but the guest OS cannot allocate 64-bit address space for it.

### ESXi vmware.log Shows Correct Mapping
```
PCIPassthru: Device 0000:42:00.0 barIndex 0 type 2 realaddr 0xd4000000 size 16777216 flags 0
PCIPassthru: Device 0000:42:00.0 barIndex 1 type 3 realaddr 0x3b800000000 size 34359738368 flags 12
PCIPassthru: Device 0000:42:00.0 barIndex 3 type 3 realaddr 0x3b7fe000000 size 33554432 flags 12
PCIPassthru: successfully created the IOMMU mappings
```

---

## Workarounds Applied

### 1. NVIDIA Driver Module Options

Create `/etc/modprobe.d/nvidia-bar.conf`:
```bash
options nvidia NVreg_EnableResizableBar=0 NVreg_EnableGpuFirmware=0
```

Apply:
```bash
sudo update-initramfs -u
sudo reboot
```

### 2. Disable Nouveau Driver
```bash
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u
```

---

## CLI Commands Reference

### ESXi Host Commands

```bash
# SSH to ESXi
ssh root@192.168.1.144

# List all VMs with IDs
vim-cmd vmsvc/getallvms

# Power operations
vim-cmd vmsvc/power.on 125
vim-cmd vmsvc/power.off 125
vim-cmd vmsvc/reload 125

# Check VM status
vim-cmd vmsvc/get.summary 125 | grep -E "powerState|ipAddress"

# List GPU passthrough status
esxcli hardware pci pcipassthru list | grep -A2 -i nvidia

# View GPU PCI info
lspci | grep -i nvidia

# Check VM log for passthrough issues
grep -i "bar\|passthru\|mmio" /vmfs/volumes/datastore1/k3s-gpu-agent/vmware.log | tail -40

# Add VMX settings (power off VM first)
vim-cmd vmsvc/power.off 125
cat >> /vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx << 'EOF'
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"
hypervisor.cpuid.v0 = "FALSE"
EOF
vim-cmd vmsvc/reload 125
vim-cmd vmsvc/power.on 125

# Remove duplicate VMX entries
awk '!seen[$0]++' /vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx > /tmp/clean.vmx
mv /tmp/clean.vmx /vmfs/volumes/datastore1/k3s-gpu-agent/k3s-gpu-agent.vmx
vim-cmd vmsvc/reload 125
```

### Jump Host Commands (ocp-svc)

```bash
# SSH to jump host
ssh root@192.168.1.238

# Test GPU agent connectivity
ping -c 2 192.168.22.82

# SSH to GPU agent with password
sshpass -p 'Andrea24!!' ssh dare@192.168.22.82 "nvidia-smi"

# Check GPU visibility
sshpass -p 'Andrea24!!' ssh dare@192.168.22.82 "lspci | grep -i nvidia"

# Check BAR mapping in guest
sshpass -p 'Andrea24!!' ssh dare@192.168.22.82 "lspci -vvv -s 05:00.0 | grep -i region"

# Check dmesg for NVIDIA errors
sshpass -p 'Andrea24!!' ssh dare@192.168.22.82 "dmesg | grep -i 'nvrm\|nvidia' | tail -20"

# Interactive SSH (for sudo commands)
ssh dare@192.168.22.82
# Password: Andrea24!!
```

### GPU Agent Commands (k3s-gpu-agent)

```bash
# Check GPU
nvidia-smi

# Check PCI devices
lspci | grep -i nvidia
lspci -vvv -s 05:00.0

# Check kernel messages
dmesg | grep -i nvidia
dmesg | grep -i nvrm

# Check loaded modules
lsmod | grep nvidia

# Reload NVIDIA driver
sudo modprobe -r nvidia_uvm nvidia_drm nvidia_modeset nvidia
sudo modprobe nvidia

# Check module options
cat /etc/modprobe.d/nvidia-bar.conf

# Update initramfs after modprobe changes
sudo update-initramfs -u
sudo reboot
```

---

## Troubleshooting Flowchart

```
1. Check BIOS Settings
   └─> VT-d Enabled? Memory Mapped I/O above 4GB Enabled?
       └─> No: Enable in BIOS, reboot server
       └─> Yes: Continue

2. Check ESXi Passthrough
   └─> esxcli hardware pci pcipassthru list | grep 42:00.0
       └─> Enabled=false: Enable passthrough, reboot ESXi
       └─> Enabled=true: Continue

3. Check VMX Settings
   └─> grep pciPassthru /vmfs/volumes/.../k3s-gpu-agent.vmx
       └─> Missing 64bitMMIO: Add settings, reload VM
       └─> Present: Continue

4. Check Guest BAR Mapping
   └─> lspci -vvv -s 05:00.0 | grep Region
       └─> BAR1 <unassigned>: Apply nvidia module options
       └─> BAR1 has address: Check nvidia-smi

5. Check NVIDIA Driver
   └─> nvidia-smi
       └─> No devices: Check dmesg | grep nvrm
       └─> Shows GPU: SUCCESS!
```

---

## SOLUTION: EFI Firmware VM (RESOLVED)

The BAR1 unassigned issue was **RESOLVED** by creating an EFI-based VM instead of BIOS-based.

### Root Cause
BIOS firmware cannot allocate 64-bit address space for GPU BARs larger than 4GB. The Tesla P40 has a 32GB BAR1 (GPU memory aperture) that requires 64-bit addressing.

### Solution
Create the GPU VM with **EFI firmware** instead of BIOS:
```vmx
firmware = "efi"
```

### Working EFI VM Details

| Component | Details |
|-----------|---------|
| VM Name | k3s-gpu-efi |
| VMID | 126 |
| IP Address | 192.168.22.96 |
| Firmware | EFI |
| GPU BAR1 | Properly mapped at 1ff000000000 (32GB) |

### Verified Working BAR Mapping
```bash
$ lspci -vvv -s 0b:00.0 | grep Region
Region 0: Memory at fd000000 (32-bit, non-prefetchable) [size=16M]
Region 1: Memory at 1ff000000000 (64-bit, prefetchable) [size=32G]   # <-- CORRECT!
Region 3: Memory at 1fffe0000000 (64-bit, prefetchable) [size=32M]
```

### EFI VM VMX Configuration
```vmx
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
displayName = "k3s-gpu-efi"
guestOS = "ubuntu-64"
firmware = "efi"                              # CRITICAL: Use EFI not BIOS
numvcpus = "8"
memSize = "16384"
sched.mem.min = "16384"
sched.mem.minSize = "16384"
sched.mem.pin = "TRUE"
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
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"                 # Use lsilogic for Ubuntu installer
scsi0:0.present = "TRUE"
scsi0:0.fileName = "k3s-gpu-efi.vmdk"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "vmxnet3"
ethernet0.networkName = "VM Network"
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "128"
hypervisor.cpuid.v0 = "FALSE"
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"
pciPassthru0.deviceId = "0x1b38"
pciPassthru0.vendorId = "0x10de"
```

---

## Next Steps (After EFI VM Created)

Run these commands from the jump host (ocp-svc @ 192.168.1.238):

### 1. Install NVIDIA Driver
```bash
# SSH to the new EFI GPU VM
sshpass -p 'Andrea24!!' ssh dare@192.168.22.96

# On the GPU VM:
# Blacklist nouveau
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u

# Install build dependencies
sudo apt-get update
sudo apt-get install -y build-essential linux-headers-$(uname -r) dkms

# Download and install NVIDIA driver
wget https://us.download.nvidia.com/tesla/535.230.02/NVIDIA-Linux-x86_64-535.230.02.run -O /tmp/nvidia.run
sudo bash /tmp/nvidia.run --silent --no-questions --dkms

# Verify
nvidia-smi
```

### 2. Install K3s Agent
```bash
# Get token from K3s server (192.168.22.98)
K3S_TOKEN=$(ssh dare@192.168.22.98 "sudo cat /var/lib/rancher/k3s/server/node-token")

# Install K3s agent on GPU VM
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.22.98:6443 K3S_TOKEN=${K3S_TOKEN} sh -

# Verify node joined
kubectl get nodes
```

### 3. Install GPU Operator
```bash
# On K3s server (192.168.22.98)
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true
```

### 4. Configure Time-Slicing (4 replicas)
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  tesla-p40: |-
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4
EOF

kubectl patch clusterpolicy cluster-policy \
  -n gpu-operator \
  --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"tesla-p40"}}}}'
```

---

## Alternative Solutions (If BAR Issue Persists)

### Option 1: Use vGPU Instead of Passthrough
- Requires NVIDIA vGPU license
- Better compatibility with ESXi
- Allows GPU sharing between VMs

### Option 2: Bare Metal K3s
- Install K3s directly on physical server
- Eliminates virtualization layer
- Full GPU access guaranteed

### Option 3: Different Hypervisor
- Proxmox VE has better GPU passthrough support
- KVM/QEMU with proper IOMMU groups

---

## Document History

| Date | Change |
|------|--------|
| 2024-12-10 | Initial documentation |
| 2024-12-10 | Added BIOS settings (Dell R720xd) |
| 2024-12-10 | Added BAR1 unassigned troubleshooting |
| 2024-12-10 | Added NVIDIA module options workaround |
| 2024-12-10 | Added comprehensive CLI commands |
| 2024-12-10 | **RESOLVED**: Added EFI firmware solution |
| 2024-12-10 | Added working EFI VM configuration |
| 2024-12-10 | Added next steps for driver and K3s setup |
