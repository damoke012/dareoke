#!/bin/bash
# Honeywell Forge Cognition - K3s Uninstall Script
# Clean removal of K3s and GPU components

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=============================================="
echo "  K3s Uninstall"
echo "=============================================="
echo ""

# Check for K3s uninstall script
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    log_info "Running K3s uninstall script..."
    /usr/local/bin/k3s-uninstall.sh
else
    log_warn "K3s uninstall script not found - K3s may not be installed"
fi

# Clean up NVIDIA device plugin config
if [ -d /etc/rancher/k3s ]; then
    log_info "Cleaning up K3s configuration..."
    rm -rf /etc/rancher/k3s
fi

# Remove Helm repos
if command -v helm &> /dev/null; then
    log_info "Removing Helm repos..."
    helm repo remove nvdp 2>/dev/null || true
fi

# Clean up profile additions
if [ -f /etc/profile.d/k3s.sh ]; then
    rm -f /etc/profile.d/k3s.sh
fi

log_info "K3s uninstall complete"
echo ""
echo "Note: NVIDIA drivers and container toolkit were NOT removed."
echo "To remove them, run:"
echo "  apt remove nvidia-container-toolkit"
echo "  apt autoremove"
