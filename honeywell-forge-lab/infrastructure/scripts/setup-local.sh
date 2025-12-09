#!/bin/bash
# Honeywell Forge Cognition - Local Setup Script
# Sets up your local machine to run the deployment
#
# This installs:
#   - Ansible (for infrastructure automation)
#   - kubectl (for Kubernetes management)
#   - helm (for Kubernetes packages)
#
# Usage:
#   ./setup-local.sh
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=============================================="
echo "  Local Development Setup"
echo "=============================================="
echo ""

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    OS="windows"
else
    log_warn "Unknown OS: $OSTYPE"
    OS="linux"
fi

log_info "Detected OS: $OS"

# Install Ansible
log_info "Checking Ansible..."
if command -v ansible &> /dev/null; then
    log_info "Ansible already installed: $(ansible --version | head -1)"
else
    log_info "Installing Ansible..."
    pip3 install --user ansible
fi

# Install kubectl
log_info "Checking kubectl..."
if command -v kubectl &> /dev/null; then
    log_info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    log_info "Installing kubectl..."
    if [[ "$OS" == "linux" ]]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    elif [[ "$OS" == "macos" ]]; then
        brew install kubectl
    fi
fi

# Install Helm
log_info "Checking Helm..."
if command -v helm &> /dev/null; then
    log_info "Helm already installed: $(helm version --short)"
else
    log_info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Generate SSH key if not present
log_info "Checking SSH key..."
if [[ ! -f ~/.ssh/id_rsa ]]; then
    log_warn "No SSH key found. Generating..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    log_info "SSH key generated at ~/.ssh/id_rsa"
    echo ""
    echo "Copy this public key to your lab machine:"
    echo "----------------------------------------"
    cat ~/.ssh/id_rsa.pub
    echo "----------------------------------------"
    echo ""
    echo "On the lab machine, add it to /root/.ssh/authorized_keys"
else
    log_info "SSH key exists at ~/.ssh/id_rsa"
fi

echo ""
log_info "=============================================="
log_info "  Local Setup Complete!"
log_info "=============================================="
echo ""
echo "Next steps:"
echo "  1. Update inventory/lab.yaml with your lab machine IP"
echo "  2. Copy SSH key to lab machine: ssh-copy-id root@<LAB_IP>"
echo "  3. Run deployment: ./scripts/deploy-to-lab.sh"
echo ""
