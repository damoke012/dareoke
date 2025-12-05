# GPU Passthrough Quick Reference

## Quick Commands

### Find GPU PCI Address
```bash
lspci | grep -i nvidia
# Output: 0000:42:00.0 3D controller: NVIDIA Corporation GP102GL [Tesla P40]
```

### Enable Passthrough (one-time setup)
```bash
esxcli hardware pci pcipassthru set -d 0000:42:00.0 -e true
esxcli system settings kernel set -s iovDisableIR -v TRUE
reboot
```

### Verify Passthrough Status
```bash
vmkchdev -l | grep 42:00
# Should show: passthru (NOT vmkernel)
```

### Convert PCI Address for VMX
| Hex Bus | Decimal Bus | VMX Format |
|---------|-------------|------------|
| 0x42 | 66 | 0:66:0.0 |
| 0x3b | 59 | 0:59:0.0 |
| 0x86 | 134 | 0:134:0.0 |

Quick conversion: `echo $((16#42))` → 66

### VMX Configuration (ESXi 8 / HW v21)
```
pciPassthru0.present = "TRUE"
pciPassthru0.id = "0:66:0.0"           # DECIMAL bus number!
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "64"
sched.mem.pin = "TRUE"
sched.mem.min = "16384"                # Match VM memory
sched.mem.minSize = "16384"
```

### Automation Script
```bash
./configure-gpu-passthrough.sh ocp-w-1 0000:42:00.0
```

### Troubleshooting
```bash
# Check vmware.log for errors
tail -50 /vmfs/volumes/datastore1/ocp-w-1/vmware.log | grep -iE 'fail|error|pci'

# Common fixes:
# - "pages exceeds limit" → Add sched.mem.pin and 64bitMMIO
# - "Failed to find device" → Use decimal bus number in pciPassthru0.id
# - "BAR limit exceeded" → Enable "Above 4G Decoding" in BIOS
```

## OpenShift Node Commands

```bash
# Drain node before GPU changes
oc adm drain ocp-w-1.lab.ocp.lan --ignore-daemonsets --delete-emptydir-data --disable-eviction

# Uncordon after GPU is working
oc adm uncordon ocp-w-1.lab.ocp.lan

# Verify GPU in node
ssh core@ocp-w-1.lab.ocp.lan "lspci | grep -i nvidia"
```
