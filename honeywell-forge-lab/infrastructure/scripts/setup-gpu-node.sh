#!/bin/bash
# =============================================================================
# Setup GPU Node Dependencies for K3s + GPU Operator
# =============================================================================
#
# This script prepares a K3s agent node for GPU workloads by:
#   1. Installing NVIDIA driver prerequisites
#   2. Configuring kernel parameters for GPU passthrough
#   3. Blacklisting nouveau driver
#   4. Setting up containerd for NVIDIA runtime
#
# IMPORTANT: GPU passthrough must be configured in the hypervisor (ESXi/vSphere)
# before running this script. This script handles the OS-level configuration.
#
# Usage:
#   # Run on the GPU agent node directly
#   sudo ./setup-gpu-node.sh
#
#   # Or run remotely via SSH
#   K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret ./setup-gpu-node.sh --remote
#
# =============================================================================

set -euo pipefail

# Configuration
K3S_AGENT_IP="${K3S_AGENT_IP:-}"
VM_USER="${VM_USER:-dare}"
VM_PASSWORD="${VM_PASSWORD:-}"
REBOOT_REQUIRED=false

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

# Remote execution helper
remote_cmd() {
    local cmd="$1"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "${VM_USER}@${K3S_AGENT_IP}" "$cmd"
}

remote_sudo() {
    local cmd="$1"
    sshpass -p "${VM_PASSWORD}" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "${VM_USER}@${K3S_AGENT_IP}" \
        "echo '${VM_PASSWORD}' | sudo -S bash -c '$cmd'" 2>&1 | grep -v "^\[sudo\] password"
}

remote_copy() {
    local src="$1"
    local dst="$2"
    sshpass -p "${VM_PASSWORD}" scp -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        "$src" "${VM_USER}@${K3S_AGENT_IP}:${dst}"
}

# Check if GPU is visible to the OS
check_gpu_visible() {
    log_step "Checking if GPU is visible to the OS..."

    if lspci | grep -i nvidia &>/dev/null; then
        log_info "NVIDIA GPU detected:"
        lspci | grep -i nvidia
        return 0
    else
        log_warn "No NVIDIA GPU detected via lspci"
        log_warn "Ensure GPU passthrough is configured in the hypervisor"
        return 1
    fi
}

# Install kernel headers and build tools
install_build_deps() {
    log_step "Installing build dependencies..."

    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y \
            build-essential \
            linux-headers-$(uname -r) \
            dkms \
            pciutils
    elif command -v yum &>/dev/null; then
        yum install -y \
            kernel-devel-$(uname -r) \
            kernel-headers-$(uname -r) \
            gcc \
            make \
            dkms \
            pciutils
    else
        log_error "Unsupported package manager"
        exit 1
    fi

    log_info "Build dependencies installed"
}

# Blacklist nouveau driver
blacklist_nouveau() {
    log_step "Blacklisting nouveau driver..."

    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    # Update initramfs
    if command -v update-initramfs &>/dev/null; then
        update-initramfs -u
        REBOOT_REQUIRED=true
    elif command -v dracut &>/dev/null; then
        dracut --force
        REBOOT_REQUIRED=true
    fi

    log_info "Nouveau driver blacklisted"
}

# Configure kernel parameters for GPU passthrough
configure_kernel_params() {
    log_step "Configuring kernel parameters..."

    local grub_file=""
    if [[ -f /etc/default/grub ]]; then
        grub_file="/etc/default/grub"
    fi

    if [[ -n "$grub_file" ]]; then
        # Add IOMMU settings if not present
        if ! grep -q "intel_iommu=on" "$grub_file"; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt /' "$grub_file"

            # Update grub
            if command -v update-grub &>/dev/null; then
                update-grub
            elif command -v grub2-mkconfig &>/dev/null; then
                grub2-mkconfig -o /boot/grub2/grub.cfg
            fi

            REBOOT_REQUIRED=true
            log_info "Kernel parameters updated"
        else
            log_info "Kernel parameters already configured"
        fi
    fi
}

# Configure containerd for NVIDIA runtime (K3s specific)
configure_containerd_nvidia() {
    log_step "Configuring containerd for NVIDIA runtime..."

    # K3s uses a different containerd config location
    local k3s_config_dir="/var/lib/rancher/k3s/agent/etc/containerd"

    if [[ -d "$k3s_config_dir" ]]; then
        log_info "K3s containerd config directory exists"
        # The GPU Operator will configure this automatically
        log_info "GPU Operator will configure containerd runtime"
    else
        log_info "K3s not yet installed - containerd will be configured after K3s install"
    fi
}

# Create K3s registries config for private registry
create_registries_config() {
    local registry_url="${1:-}"

    if [[ -z "$registry_url" ]]; then
        return 0
    fi

    log_step "Creating K3s registries config for ${registry_url}..."

    mkdir -p /etc/rancher/k3s

    cat > /etc/rancher/k3s/registries.yaml << EOF
mirrors:
  "nvcr.io":
    endpoint:
      - "https://${registry_url}"
  "registry.k8s.io":
    endpoint:
      - "https://${registry_url}"
configs:
  "${registry_url}":
    tls:
      insecure_skip_verify: true
EOF

    log_info "Registries config created at /etc/rancher/k3s/registries.yaml"
}

# Verify NVIDIA driver is loaded (post-reboot check)
verify_nvidia_driver() {
    log_step "Verifying NVIDIA driver..."

    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi
        return 0
    else
        log_warn "nvidia-smi not found - driver will be installed by GPU Operator"
        return 0
    fi
}

# Main setup function
setup_local() {
    echo ""
    log_step "=============================================="
    log_step "  GPU Node Setup"
    log_step "=============================================="
    echo ""

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    check_gpu_visible || log_warn "Continuing anyway - GPU might become visible after reboot"
    install_build_deps
    blacklist_nouveau
    configure_kernel_params
    configure_containerd_nvidia

    if [[ -n "${REGISTRY_URL:-}" ]]; then
        create_registries_config "${REGISTRY_URL}"
    fi

    echo ""
    log_step "=============================================="
    log_step "  GPU Node Setup Complete"
    log_step "=============================================="
    echo ""

    if [[ "$REBOOT_REQUIRED" == "true" ]]; then
        log_warn "REBOOT REQUIRED to apply kernel changes"
        log_warn "After reboot, the GPU Operator will install the NVIDIA driver"
        echo ""
        read -p "Reboot now? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            reboot
        fi
    else
        log_info "No reboot required"
    fi
}

# Remote setup function
setup_remote() {
    if [[ -z "${K3S_AGENT_IP}" ]]; then
        log_error "K3S_AGENT_IP is required for remote setup"
        exit 1
    fi

    if [[ -z "${VM_PASSWORD}" ]]; then
        log_error "VM_PASSWORD is required for remote setup"
        exit 1
    fi

    echo ""
    log_step "=============================================="
    log_step "  Remote GPU Node Setup: ${K3S_AGENT_IP}"
    log_step "=============================================="
    echo ""

    # Check GPU visibility
    log_step "Checking GPU visibility on ${K3S_AGENT_IP}..."
    remote_sudo "lspci | grep -i nvidia" || log_warn "No NVIDIA GPU detected"

    # Install dependencies
    log_step "Installing build dependencies..."
    remote_sudo "apt-get update && apt-get install -y build-essential linux-headers-\$(uname -r) dkms pciutils 2>/dev/null || yum install -y kernel-devel-\$(uname -r) kernel-headers-\$(uname -r) gcc make dkms pciutils"

    # Blacklist nouveau
    log_step "Blacklisting nouveau driver..."
    remote_sudo "cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF"
    remote_sudo "update-initramfs -u 2>/dev/null || dracut --force 2>/dev/null || true"

    # Create registries config if REGISTRY_URL is set
    if [[ -n "${REGISTRY_URL:-}" ]]; then
        log_step "Creating registries config..."
        remote_sudo "mkdir -p /etc/rancher/k3s"
        remote_sudo "cat > /etc/rancher/k3s/registries.yaml << 'EOF'
mirrors:
  \"nvcr.io\":
    endpoint:
      - \"https://${REGISTRY_URL}\"
  \"registry.k8s.io\":
    endpoint:
      - \"https://${REGISTRY_URL}\"
configs:
  \"${REGISTRY_URL}\":
    tls:
      insecure_skip_verify: true
EOF"
    fi

    echo ""
    log_step "=============================================="
    log_step "  Remote GPU Node Setup Complete"
    log_step "=============================================="
    echo ""
    log_warn "REBOOT REQUIRED on ${K3S_AGENT_IP} to apply kernel changes"
    echo ""
    read -p "Reboot ${K3S_AGENT_IP} now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remote_sudo "reboot" || true
        log_info "Reboot initiated on ${K3S_AGENT_IP}"
    fi
}

# Show help
show_help() {
    cat << EOF
GPU Node Setup Script for K3s + GPU Operator

This script prepares a node for GPU workloads by:
  - Installing kernel headers and build tools
  - Blacklisting the nouveau driver
  - Configuring kernel parameters for GPU passthrough
  - Setting up K3s registries for private registry (optional)

IMPORTANT: GPU passthrough must be configured in the hypervisor BEFORE running this.

Usage:
  # Run locally (as root)
  sudo ./setup-gpu-node.sh

  # Run remotely on GPU agent node
  K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret ./setup-gpu-node.sh --remote

Environment Variables:
  K3S_AGENT_IP    GPU agent node IP (for --remote)
  VM_USER         SSH username (default: dare)
  VM_PASSWORD     SSH password (required for --remote)
  REGISTRY_URL    Private registry URL (optional)

Options:
  --remote        Run setup on remote node via SSH
  --check         Check GPU visibility only
  --help, -h      Show this help

Examples:
  # Local setup
  sudo ./setup-gpu-node.sh

  # Remote setup with private registry
  K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret REGISTRY_URL=harbor.example.com/nvidia ./setup-gpu-node.sh --remote

  # Check GPU visibility
  K3S_AGENT_IP=192.168.1.101 VM_PASSWORD=secret ./setup-gpu-node.sh --check
EOF
}

# Main
case "${1:-}" in
    --remote)
        setup_remote
        ;;
    --check)
        if [[ -n "${K3S_AGENT_IP}" ]]; then
            log_info "Checking GPU on ${K3S_AGENT_IP}..."
            remote_sudo "lspci | grep -i nvidia || echo 'No NVIDIA GPU found'"
            remote_sudo "lsmod | grep -E 'nvidia|nouveau' || echo 'No GPU modules loaded'"
        else
            check_gpu_visible
        fi
        ;;
    --help|-h)
        show_help
        ;;
    *)
        setup_local
        ;;
esac
