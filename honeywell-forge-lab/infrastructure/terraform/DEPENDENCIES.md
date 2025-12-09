# Terraform K3s Infrastructure - Dependencies

## Required Software

### On Your Local Machine (for manual deployment)

| Software | Version | Installation |
|----------|---------|--------------|
| Terraform | >= 1.0 | `brew install terraform` or [download](https://www.terraform.io/downloads) |
| SSH client | any | Built-in on Mac/Linux |

### On ESXi Host

| Requirement | Details |
|-------------|---------|
| ESXi Version | 7.0+ recommended |
| vSphere API | Enabled (default) |
| SSH | Enabled for debugging |

### VM Template Requirements

Before running Terraform, you need a VM template in ESXi:

| Component | Requirement |
|-----------|-------------|
| OS | Ubuntu 22.04 LTS or Rocky Linux 9 |
| cloud-init | Installed and enabled |
| VMware Tools | open-vm-tools installed |
| Disk | Thin provisioned |

#### Creating the Template

```bash
# 1. Create a new VM in ESXi with Ubuntu 22.04

# 2. After OS installation, run:
sudo apt update && sudo apt upgrade -y
sudo apt install -y cloud-init open-vm-tools curl wget git

# 3. Clean cloud-init for templating
sudo cloud-init clean
sudo rm -rf /var/lib/cloud/*

# 4. Remove SSH host keys (regenerated on first boot)
sudo rm -f /etc/ssh/ssh_host_*

# 5. Clear machine ID
sudo truncate -s 0 /etc/machine-id

# 6. Shutdown
sudo shutdown -h now

# 7. In ESXi: Right-click VM -> Template -> Convert to Template
```

## GitHub Secrets (for CI/CD)

Set these secrets in your GitHub repository (Settings -> Secrets and variables -> Actions):

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `VSPHERE_SERVER` | ESXi IP address | `192.168.1.144` |
| `VSPHERE_USER` | ESXi username | `root` |
| `VSPHERE_PASSWORD` | ESXi password | `your-password` |
| `SSH_PUBLIC_KEY` | SSH public key for VM access | `ssh-rsa AAAA...` |
| `SSH_PRIVATE_KEY` | SSH private key (for Ansible) | `-----BEGIN OPENSSH...` |

### Generating SSH Keys

```bash
# Generate a new SSH key pair for the lab
ssh-keygen -t rsa -b 4096 -f ~/.ssh/honeywell-lab -N ""

# Display public key (for SSH_PUBLIC_KEY secret)
cat ~/.ssh/honeywell-lab.pub

# Display private key (for SSH_PRIVATE_KEY secret)
cat ~/.ssh/honeywell-lab
```

## Network Requirements

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 | TCP | SSH access to VMs |
| 443 | TCP | ESXi web UI / vSphere API |
| 6443 | TCP | Kubernetes API (K3s) |
| 10250 | TCP | Kubelet API |
| 8472 | UDP | Flannel VXLAN (K3s) |

## Resource Requirements

### Minimum ESXi Host Resources

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 12 cores | 16+ cores |
| RAM | 48 GB | 64+ GB |
| Storage | 400 GB | 500+ GB |

### VM Allocation

| VM | CPUs | RAM | Disk |
|----|------|-----|------|
| k3s-server | 4 | 8 GB | 100 GB |
| k3s-gpu-agent | 8 | 32 GB | 200 GB |
| **Total** | **12** | **40 GB** | **300 GB** |

## GPU Requirements (for k3s-gpu-agent)

| Requirement | Details |
|-------------|---------|
| GPU | NVIDIA Tesla P40, RTX, or similar |
| ESXi Passthrough | Must be enabled in ESXi |
| Memory Reservation | Full memory must be reserved |

### Enable GPU Passthrough

```bash
# SSH to ESXi host
ssh root@192.168.1.144

# Find GPU PCI device
lspci -v | grep -i nvidia

# Enable passthrough (requires reboot)
esxcli system settings kernel set -s vga -v FALSE

# Reboot ESXi
reboot
```

Then in vSphere UI:
1. Host -> Configure -> Hardware -> PCI Devices
2. Find NVIDIA GPU -> Toggle Passthrough -> Enable
3. Reboot host again

## Terraform State

The CI/CD pipeline stores Terraform state as a GitHub artifact. For production use, consider:

- **Terraform Cloud**: Free for small teams
- **S3 + DynamoDB**: AWS backend with locking
- **Azure Storage**: For Azure environments

### Adding Remote State (optional)

```hcl
# Add to main.tf for S3 backend
terraform {
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "honeywell-lab/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Troubleshooting

### Terraform can't connect to ESXi

```bash
# Test connectivity
curl -k https://192.168.1.144/sdk

# Check if API is enabled
# ESXi UI -> Host -> Manage -> Services -> verify "vpxd" is running
```

### Template not found

```bash
# List templates in ESXi
vim-cmd vmsvc/getallvms | grep -i template
```

### VM creation fails

```bash
# Check ESXi logs
tail -f /var/log/vmkernel.log

# Check datastore space
esxcli storage filesystem list
```

## Quick Start Checklist

- [ ] ESXi 7.0+ installed and accessible
- [ ] VM template created (Ubuntu 22.04 + cloud-init)
- [ ] SSH key pair generated
- [ ] GitHub secrets configured
- [ ] GPU passthrough enabled (if using GPU)
- [ ] Network allows required ports
