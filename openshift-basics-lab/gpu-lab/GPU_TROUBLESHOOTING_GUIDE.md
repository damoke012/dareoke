# GPU Troubleshooting Guide: NVIDIA GPU Operator on OpenShift

**Date:** December 6, 2025
**Environment:** OpenShift 4.19 on ESXi 8.0 with Tesla P40 GPU Passthrough
**Duration:** ~3 hours of troubleshooting

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Environment Details](#environment-details)
3. [Issues Encountered and Solutions](#issues-encountered-and-solutions)
4. [Learning Points](#learning-points)
5. [Commands Reference](#commands-reference)
6. [Current Status and Next Steps](#current-status-and-next-steps)

---

## Executive Summary

This document chronicles a comprehensive GPU troubleshooting session on an OpenShift cluster running on ESXi with GPU passthrough. We encountered and resolved multiple issues in sequence, ultimately identifying a hardware power issue as the final blocker.

### Issues Resolved:
- ✅ Node repeatedly going NotReady due to MCO update loop
- ✅ NVIDIA driver 550.x causing kernel BUG crashes
- ✅ GPU BAR1 memory not assignable (BIOS firmware limitation)
- ✅ Air-gapped cluster image pull failures

### Final Blocker (Hardware):
- ❌ GPU reporting "power cables not connected" - requires physical verification

---

## Environment Details

| Component | Details |
|-----------|---------|
| **OpenShift Version** | 4.19 (v1.32.7) |
| **RHCOS Version** | 9.6.20250826-1 |
| **Kernel** | 5.14.0-570.39.1.el9_6.x86_64 |
| **Hypervisor** | ESXi 8.0 |
| **GPU** | NVIDIA Tesla P40 (24GB VRAM, 250W TDP) |
| **GPU Operator** | v24.9.2 |
| **Driver Version** | 535.261.03 (changed from 550.127.08) |
| **Registry** | Harbor (air-gapped cluster) |

### Cluster Nodes:
```
ocp-cp-1.lab.ocp.lan   Ready   control-plane,master,worker
ocp-cp-2.lab.ocp.lan   Ready   control-plane,master,worker
ocp-cp-3.lab.ocp.lan   Ready   control-plane,master,worker
ocp-w-1.lab.ocp.lan    Ready   worker (GPU node)
ocp-w-2.lab.ocp.lan    Ready   worker
ocp-w-3.lab.ocp.lan    Ready   worker
```

---

## Issues Encountered and Solutions

### Issue 1: Node Repeatedly Going NotReady

**Symptoms:**
- GPU node `ocp-w-1` cycling between Ready and NotReady
- SSH connections refused intermittently
- kubelet port 10250 connection refused

**Root Cause:**
Machine Config Operator (MCO) was in an update loop, repeatedly rebooting the node.

**Diagnosis:**
```bash
# Check MCP status
oc get mcp worker
# Output showed UPDATING: True even though config was already applied

# Check node uptime pattern
ssh core@ocp-w-1.lab.ocp.lan "sudo last reboot | head -5"
# Showed reboots every 6-7 minutes
```

**Solution:**
```bash
# Pause the MachineConfigPool to stop automatic reboots
oc patch mcp worker --type merge --patch '{"spec":{"paused":true}}'
```

**Important:** Remember to unpause when GPU is working:
```bash
oc patch mcp worker --type merge --patch '{"spec":{"paused":false}}'
```

---

### Issue 2: NVIDIA Driver 550.x Causing Kernel BUG

**Symptoms:**
- Node rebooting every 6-7 minutes even with MCO paused
- Driver pod showing 18+ restarts
- Kernel BUG in logs

**Diagnosis:**
```bash
ssh core@ocp-w-1.lab.ocp.lan "sudo journalctl -k -b -1 | grep -i 'panic|oops|bug'"
# Output: kernel BUG at lib/list_debug.c:23!
# Also: Disabling lock debugging due to kernel taint
```

**Root Cause:**
Driver version 550.127.08/550.144.03 has a bug with RHEL 9.6 kernel 5.14.0-570.39.1 causing list corruption.

**Solution:**
1. Mirror stable 535.x LTS driver to Harbor:
```bash
skopeo login harbor.apps.lab.ocp.lan
skopeo copy \
  docker://nvcr.io/nvidia/driver:535.261.03-rhel9.6 \
  docker://harbor.apps.lab.ocp.lan/nvidia/driver:535.261.03-rhel9.6
```

2. Update ClusterPolicy:
```bash
oc patch clusterpolicy gpu-cluster-policy --type merge \
  -p '{"spec":{"driver":{"version":"535.261.03"}}}'
```

**Lesson:** The 535.x branch is LTS (Long Term Support) and more stable than 550.x for production.

---

### Issue 3: GPU BAR1 Memory Not Assigned

**Symptoms:**
- Driver loads but nvidia-smi shows "No devices found"
- Startup probe failing with "No devices were found"

**Diagnosis:**
```bash
ssh core@ocp-w-1.lab.ocp.lan "lspci -vvv -s 13:00.0 | grep -i region"
# Output: Region 1: Memory at <unassigned> (64-bit, prefetchable)

ssh core@ocp-w-1.lab.ocp.lan "dmesg | grep -i 'BAR 1'"
# Output: pci 0000:13:00.0: BAR 1 [mem size 0x800000000 64bit pref]: can't assign; no space
```

**Root Cause:**
VM using BIOS firmware couldn't allocate the 32GB BAR1 region for the GPU's VRAM.

**Solution:**
1. Power off the VM:
```bash
# On ESXi
vim-cmd vmsvc/power.off 117
```

2. Add EFI firmware to VMX:
```bash
echo 'firmware = "efi"' >> "/vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx"
```

3. Power on the VM:
```bash
vim-cmd vmsvc/power.on 117
```

**Verification:**
```bash
ssh core@ocp-w-1.lab.ocp.lan "lspci -vvv -s 13:00.0 | grep -i region"
# Now shows: Region 1: Memory at 1ff000000000 (64-bit, prefetchable) [size=32G]
```

**Lesson:** Large BAR GPUs (Tesla P40 = 24GB VRAM needs 32GB BAR) require EFI firmware for proper 64-bit memory addressing.

---

### Issue 4: Air-Gapped Cluster Image Pull Failures

**Symptoms:**
- GPU Operator pods stuck in ImagePullBackOff
- Trying to pull from nvcr.io (unreachable)

**Diagnosis:**
```bash
oc get pods -n nvidia-gpu-operator
# Pods showing ImagePullBackOff

oc describe pod <pod-name> -n nvidia-gpu-operator
# Error: failed to pull image from nvcr.io
```

**Root Cause:**
Cluster has no internet access; needs to use local Harbor registry.

**Solution:**
1. Mirror required images to Harbor:
```bash
skopeo copy docker://nvcr.io/nvidia/gpu-operator:v24.9.2 \
  docker://harbor.apps.lab.ocp.lan/nvidia/gpu-operator:v24.9.2
# Repeat for all required images
```

2. Configure ClusterPolicy to use Harbor:
```bash
oc get clusterpolicy gpu-cluster-policy -o yaml
# Verify repository: harbor.apps.lab.ocp.lan/nvidia
```

3. If CSV needs patching for operator image:
```bash
oc patch csv gpu-operator-certified.v24.9.2 -n nvidia-gpu-operator \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/image", "value": "harbor.apps.lab.ocp.lan/nvidia/gpu-operator:v24.9.2"}]'
```

---

### Issue 5: GPU Power Cables Not Connected (Current Blocker)

**Symptoms:**
- Driver modules load successfully
- nvidia-smi shows "No devices found"
- Repeated errors in dmesg

**Diagnosis:**
```bash
ssh core@ocp-w-1.lab.ocp.lan "dmesg | grep -i 'power cable\|nvrm' | tail -10"
# Output:
# NVRM: GPU 0000:13:00.0: GPU does not have the necessary power cables connected.
# NVRM: GPU 0000:13:00.0: RmInitAdapter failed! (0x24:0x1c:1447)
```

**Root Cause:**
The Tesla P40 requires a physical 8-pin PCIe power cable from the PSU. The GPU's power sense circuit is not detecting proper power.

**Status:** PENDING HARDWARE VERIFICATION

**Required Action:**
1. Physically access the server
2. Verify 8-pin power cable is connected to Tesla P40
3. Ensure cable is firmly seated
4. Verify PSU has sufficient wattage (P40 needs 250W)

---

## Learning Points

### OpenShift & Kubernetes

1. **Node States**: `Ready` means kubelet is healthy and posting status; `NotReady` means kubelet stopped communicating

2. **MCO (Machine Config Operator)**: Manages node configuration; will reboot nodes to apply changes; can cause update loops

3. **Pausing MCP**: Use `oc patch mcp worker --type merge --patch '{"spec":{"paused":true}}'` to stop automatic updates/reboots

4. **Pod Lifecycle States**:
   - `Init:0/1` - Running init containers
   - `PodInitializing` - Init containers done, main starting
   - `1/2 Running` - One of two containers running
   - `CrashLoopBackOff` - Container crashing repeatedly

5. **oc exec vs oc debug**:
   - `oc exec` - Run command in existing pod (fast)
   - `oc debug node/` - Create new debug pod on node (slower, for host access)

### NVIDIA GPU Operator

6. **GPU Operator Pod Dependency Chain**:
   ```
   nvidia-driver-daemonset (must be Ready first)
        ↓
   nvidia-container-toolkit-daemonset
        ↓
   nvidia-device-plugin-daemonset
        ↓
   nvidia-dcgm + nvidia-dcgm-exporter
        ↓
   gpu-feature-discovery
        ↓
   nvidia-operator-validator
   ```

7. **Driver Container Architecture**: The driver runs inside a container but loads kernel modules into the host kernel

8. **Startup Probe**: Driver pod uses `nvidia-smi && touch /run/nvidia/validations/.driver-ctr-ready` to verify GPU is working

9. **ClusterPolicy**: Central configuration for GPU Operator - controls driver version, repository, enabled components

10. **Disabling GPU on a Node**:
    ```bash
    oc label node <node> nvidia.com/gpu.deploy.operands=false
    ```

### Driver Troubleshooting

11. **Module Loading Chain**:
    ```
    PCI Device visible (lspci) → Module loaded (lsmod) →
    Driver binds to device → /dev/nvidia* created → nvidia-smi works
    ```

12. **Driver Branches**:
    - 535.x = LTS (Long Term Support) - More stable
    - 550.x = New Feature Branch - May have issues
    - 570.x+ = Newer branches

13. **Kernel Taint**: NVIDIA driver taints the kernel (`Disabling lock debugging due to kernel taint`); normal for proprietary modules

14. **Common dmesg Errors**:
    - `RmInitAdapter failed` - Driver can't initialize GPU
    - `BAR X: can't assign; no space` - Memory allocation failure
    - `power cables not connected` - Hardware power issue

### ESXi GPU Passthrough

15. **GPU Passthrough Requirements**:
    - IOMMU enabled in BIOS (Intel VT-d or AMD-Vi)
    - GPU marked for passthrough in ESXi
    - ESXi host rebooted after marking
    - PCI device added to VM

16. **VMX Settings for Large BAR GPUs**:
    ```
    pciPassthru.use64bitMMIO = "TRUE"
    pciPassthru.64bitMMIOSizeGB = "64"
    firmware = "efi"
    ```

17. **EFI vs BIOS Firmware**:
    - BIOS: Limited address space, may fail for large BAR GPUs
    - EFI: Supports 64-bit addressing, required for GPUs >4GB VRAM

18. **PCI BAR (Base Address Register)**: Memory regions the GPU needs mapped
    - BAR0: Control registers (~16MB)
    - BAR1: VRAM (24GB for P40 = needs 32GB address space)
    - BAR3: Additional resources (~32MB)

19. **Cold Boot vs Warm Reboot**: GPU passthrough issues often require cold boot (power off/on) to reset PCI state

### ESXi Commands

20. **VM Management**:
    ```bash
    vim-cmd vmsvc/power.getstate 117    # Check power state
    vim-cmd vmsvc/power.on 117          # Power on
    vim-cmd vmsvc/power.off 117         # Power off
    vim-cmd vmsvc/power.reset 117       # Hard reset
    vim-cmd vmsvc/get.config 117        # Get VM config
    vim-cmd vmsvc/get.guest 117         # Get guest info
    ```

21. **PCI Passthrough**:
    ```bash
    esxcli hardware pci pcipassthru list  # List passthrough devices
    esxcli hardware pci list              # List all PCI devices
    ```

### Hardware Requirements

22. **Tesla P40 Specifications**:
    - 24GB GDDR5X VRAM
    - 250W TDP
    - 8-pin PCIe power connector required
    - Passive cooling (requires adequate airflow)

---

## Commands Reference

### Cluster Status
```bash
# Check nodes
oc get nodes -o wide

# Check GPU pods
oc get pods -n nvidia-gpu-operator

# Check ClusterPolicy
oc get clusterpolicy gpu-cluster-policy -o yaml

# Check MCP status
oc get mcp worker
```

### Node Debugging
```bash
# SSH to node
ssh core@ocp-w-1.lab.ocp.lan

# Check nvidia modules
lsmod | grep nvidia

# Check nvidia devices
ls -la /dev/nvidia*

# Check dmesg for nvidia
dmesg | grep -i nvidia | tail -30

# Check GPU in lspci
lspci -vvv -s 13:00.0
```

### Driver Pod Debugging
```bash
# Check driver logs
oc logs <driver-pod> -n nvidia-gpu-operator -c nvidia-driver-ctr --tail=50

# Execute in driver container
oc exec -n nvidia-gpu-operator <driver-pod> -c nvidia-driver-ctr -- nvidia-smi

# Check module parameters
oc exec -n nvidia-gpu-operator <driver-pod> -c nvidia-driver-ctr -- modinfo nvidia | grep parm
```

### ESXi Commands
```bash
# Check VM power
vim-cmd vmsvc/power.getstate 117

# Check GPU passthrough
esxcli hardware pci pcipassthru list

# View VMX file
cat "/vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx"
```

---

## Current Status and Next Steps

### Current State:
- ✅ Node stable (when GPU driver disabled)
- ✅ GPU BAR memory properly assigned (EFI firmware)
- ✅ Driver 535.261.03 loads without kernel crashes
- ✅ MCP paused (remember to unpause later)
- ❌ GPU reporting power cable not connected

### GPU Currently Disabled:
```bash
# GPU operator operands disabled on the node
oc get node ocp-w-1.lab.ocp.lan --show-labels | grep operands
# nvidia.com/gpu.deploy.operands=false
```

### To Resume After Hardware Fix:

1. **Verify power cable is connected** to Tesla P40

2. **Re-enable GPU on node:**
   ```bash
   oc label node ocp-w-1.lab.ocp.lan nvidia.com/gpu.deploy.operands-
   ```

3. **Watch pods come up:**
   ```bash
   oc get pods -n nvidia-gpu-operator -w
   ```

4. **Verify GPU working:**
   ```bash
   ssh core@ocp-w-1.lab.ocp.lan "ls -la /dev/nvidia*"
   oc exec -n nvidia-gpu-operator <driver-pod> -c nvidia-driver-ctr -- nvidia-smi
   ```

5. **Unpause MCP when stable:**
   ```bash
   oc patch mcp worker --type merge --patch '{"spec":{"paused":false}}'
   ```

---

## Appendix: Full Error Messages Encountered

### Kernel BUG (Driver 550.x)
```
kernel BUG at lib/list_debug.c:23!
Disabling lock debugging due to kernel taint
```

### BAR Assignment Failure (BIOS Firmware)
```
pci 0000:13:00.0: BAR 1 [mem size 0x800000000 64bit pref]: can't assign; no space
NVRM: This PCI I/O region assigned to your NVIDIA device is invalid:
NVRM: BAR1 is 0M @ 0x0 (PCI:0000:13:00.0)
```

### Power Cable Error (Current)
```
NVRM: GPU 0000:13:00.0: GPU does not have the necessary power cables connected.
NVRM: GPU 0000:13:00.0: RmInitAdapter failed! (0x24:0x1c:1447)
NVRM: GPU 0000:13:00.0: rm_init_adapter failed, device minor number 0
```

---

*Document created during troubleshooting session on December 6, 2025*
