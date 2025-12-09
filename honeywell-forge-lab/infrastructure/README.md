# Infrastructure as Code - Honeywell Forge Cognition

Automated deployment of K3s + GPU support + Forge Cognition to your lab environment.

## Quick Start

```bash
# 1. Setup local machine (installs Ansible, kubectl, helm)
./scripts/setup-local.sh

# 2. Update inventory with your lab machine IP
vim ansible/inventory/lab.yaml
# Change: ansible_host: 192.168.1.100

# 3. Copy SSH key to lab machine
ssh-copy-id root@<YOUR_LAB_IP>

# 4. Deploy everything
./scripts/deploy-to-lab.sh

# 5. Validate deployment
./scripts/test-lab.sh <YOUR_LAB_IP>
```

## Directory Structure

```
infrastructure/
├── ansible/
│   ├── inventory/
│   │   └── lab.yaml              # Lab machine configuration
│   └── playbooks/
│       └── deploy-all.yaml       # Main deployment playbook
├── terraform/
│   ├── main.tf                   # vSphere VM provisioning (optional)
│   └── terraform.tfvars.example  # Example variables
├── scripts/
│   ├── setup-local.sh            # Setup your local machine
│   ├── deploy-to-lab.sh          # One-command deployment
│   └── test-lab.sh               # Validation tests
└── README.md
```

## Prerequisites

### Your Local Machine
- SSH access to lab machine
- Python 3.8+
- pip

### Lab Machine
- Ubuntu 22.04 (recommended) or RHEL 8/9
- NVIDIA GPU (Tesla P40, RTX, etc.)
- Root SSH access
- Internet access (for package downloads)

## Deployment Options

### Option A: Existing VM (Recommended for Lab)

If you already have a VM with GPU passthrough:

```bash
# 1. Update inventory
vim ansible/inventory/lab.yaml
# Set ansible_host to your VM IP

# 2. Ensure SSH access
ssh-copy-id root@<VM_IP>

# 3. Deploy
./scripts/deploy-to-lab.sh
```

### Option B: Provision New VM with Terraform

If using vSphere/ESXi to create the VM:

```bash
cd terraform

# 1. Configure variables
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 2. Initialize and apply
terraform init
terraform plan
terraform apply

# 3. Enable GPU passthrough in vSphere UI
# (Manual step - see below)

# 4. Deploy K3s + Forge with Ansible
cd ../scripts
./deploy-to-lab.sh
```

## Ansible Playbook Phases

The `deploy-all.yaml` playbook runs these phases:

| Phase | Description | Tags |
|-------|-------------|------|
| 1 | Base system packages | `base` |
| 2 | NVIDIA drivers | `gpu` |
| 3 | NVIDIA Container Toolkit | `gpu` |
| 4 | K3s installation | `k3s` |
| 5 | containerd NVIDIA config | `gpu`, `k3s` |
| 6 | NVIDIA Device Plugin | `gpu` |
| 7 | Forge Cognition deploy | `forge` |
| 8 | Verification | `verify` |

### Run Specific Phases

```bash
# Only K3s installation
./scripts/deploy-to-lab.sh --tags k3s

# Only GPU setup
./scripts/deploy-to-lab.sh --tags gpu

# Only Forge application
./scripts/deploy-to-lab.sh --tags forge

# K3s + GPU (skip Forge)
./scripts/deploy-to-lab.sh --tags k3s,gpu
```

## Configuration

### Inventory Variables

Edit `ansible/inventory/lab.yaml`:

```yaml
all:
  vars:
    # K3s version
    k3s_version: "v1.28.4+k3s1"

    # GPU time-slicing (virtual GPUs)
    gpu_time_slices: 4

    # NVIDIA driver version
    nvidia_driver_version: "535"

  children:
    lab:
      hosts:
        lab-gpu-01:
          ansible_host: 192.168.1.100  # <-- YOUR IP HERE
          gpu_type: "tesla_p40"
```

### GPU Time-Slicing

The `gpu_time_slices` variable controls how many virtual GPUs are created:

| Setting | Physical GPU | Virtual GPUs |
|---------|--------------|--------------|
| `gpu_time_slices: 2` | 1x Tesla P40 | 2x nvidia.com/gpu |
| `gpu_time_slices: 4` | 1x Tesla P40 | 4x nvidia.com/gpu |
| `gpu_time_slices: 8` | 1x Tesla P40 | 8x nvidia.com/gpu |

Recommended settings:
- Tesla P40 (24GB): 2-4 slices
- Jetson Thor (128GB): 4-8 slices
- RTX Pro 4000 (20GB): 2-4 slices

## Validation

After deployment, run the test script:

```bash
./scripts/test-lab.sh 192.168.1.100
```

This checks:
1. SSH connectivity
2. NVIDIA driver
3. K3s status
4. Kubernetes nodes
5. GPU time-slicing
6. NVIDIA device plugin
7. Forge namespace
8. Inference server pod
9. Health endpoint
10. GPU access from pods

## Troubleshooting

### SSH Connection Failed
```bash
# Check connectivity
ping <LAB_IP>

# Test SSH
ssh -v root@<LAB_IP>

# Copy key if needed
ssh-copy-id root@<LAB_IP>
```

### NVIDIA Driver Issues
```bash
# SSH to lab machine
ssh root@<LAB_IP>

# Check driver
nvidia-smi

# If not working, reinstall
apt remove --purge nvidia-*
apt install nvidia-driver-535
reboot
```

### K3s Not Starting
```bash
# Check K3s status
systemctl status k3s

# View logs
journalctl -u k3s -f

# Restart
systemctl restart k3s
```

### GPU Not Visible in Kubernetes
```bash
# Check device plugin
kubectl get pods -n nvidia-device-plugin

# Check node allocatable
kubectl describe node | grep -A5 Allocatable

# Check RuntimeClass
kubectl get runtimeclass nvidia
```

### Forge Pod Pending
```bash
# Check pod status
kubectl describe pod -n forge-cognition -l app=inference-server

# Common issues:
# - "Insufficient nvidia.com/gpu" → Check time-slicing config
# - "PVC not bound" → Check storage class
# - "ImagePullBackOff" → Check image name/registry
```

## GPU Passthrough (ESXi/vSphere)

If using vSphere, enable GPU passthrough:

1. **ESXi Host Configuration**
   ```bash
   # SSH to ESXi host
   esxcli system settings kernel set -s vga -v FALSE
   reboot
   ```

2. **vSphere UI**
   - Host → Configure → Hardware → PCI Devices
   - Find NVIDIA GPU → Toggle Passthrough
   - Reboot ESXi host

3. **VM Configuration**
   - VM → Edit Settings → Add New Device → PCI Device
   - Select the NVIDIA GPU
   - Reserve all memory

4. **Verify in VM**
   ```bash
   lspci | grep -i nvidia
   nvidia-smi
   ```

## Cleanup

### Remove Forge Only
```bash
ssh root@<LAB_IP> "kubectl delete namespace forge-cognition"
```

### Remove K3s
```bash
ssh root@<LAB_IP> "/usr/local/bin/k3s-uninstall.sh"
```

### Destroy Terraform VM
```bash
cd terraform
terraform destroy
```

## Next Steps

After successful deployment:

1. **Access the inference server**
   ```bash
   curl http://<LAB_IP>:30080/health
   ```

2. **Load a test model** (when available)
   ```bash
   scp model.tar.gz root@<LAB_IP>:/opt/forge/models/
   ```

3. **Run benchmarks**
   ```bash
   python benchmarks/benchmark_inference.py --host http://<LAB_IP>:30080
   ```

4. **View logs**
   ```bash
   ssh root@<LAB_IP> "kubectl logs -f deployment/inference-server -n forge-cognition"
   ```
