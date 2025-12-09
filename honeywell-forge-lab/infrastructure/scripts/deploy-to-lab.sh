#!/bin/bash
# Honeywell Forge Cognition - Deploy to Lab Script
# One-command deployment to your lab environment
#
# Usage:
#   ./deploy-to-lab.sh                    # Full deployment
#   ./deploy-to-lab.sh --check            # Dry run (no changes)
#   ./deploy-to-lab.sh --tags k3s,gpu     # Only K3s and GPU
#   ./deploy-to-lab.sh --skip-reboot      # Don't reboot after driver install
#
# Prerequisites:
#   1. Update inventory/lab.yaml with your lab machine IP
#   2. Ensure SSH key access to lab machine
#   3. Install Ansible: pip install ansible
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/.."
ANSIBLE_DIR="${INFRA_DIR}/ansible"

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

# Default values
CHECK_MODE=""
EXTRA_ARGS=""
TAGS=""
SKIP_REBOOT=""
LAB_HOST=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --check|--dry-run)
            CHECK_MODE="--check"
            shift
            ;;
        --tags)
            TAGS="--tags $2"
            shift 2
            ;;
        --skip-reboot)
            SKIP_REBOOT="-e skip_reboot=true"
            shift
            ;;
        --host)
            LAB_HOST="$2"
            shift 2
            ;;
        -v|--verbose)
            EXTRA_ARGS="-vvv"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--check] [--tags TAG] [--skip-reboot] [--host IP] [-v]"
            exit 1
            ;;
    esac
done

echo "=============================================="
echo "  Honeywell Forge Cognition - Lab Deployment"
echo "=============================================="
echo ""

# Check for Ansible
log_step "Checking prerequisites..."
if ! command -v ansible-playbook &> /dev/null; then
    log_error "Ansible not found. Install with: pip install ansible"
    exit 1
fi
log_info "Ansible found: $(ansible --version | head -1)"

# Check inventory file
INVENTORY="${ANSIBLE_DIR}/inventory/lab.yaml"
if [[ ! -f "$INVENTORY" ]]; then
    log_error "Inventory file not found: $INVENTORY"
    exit 1
fi

# Update host IP if provided
if [[ -n "$LAB_HOST" ]]; then
    log_info "Updating lab host IP to: $LAB_HOST"
    sed -i "s/ansible_host: .*/ansible_host: $LAB_HOST/" "$INVENTORY"
fi

# Show current target
log_info "Target hosts from inventory:"
grep -A1 "lab-gpu-01:" "$INVENTORY" | grep ansible_host || log_warn "No host configured"

# Confirm deployment
if [[ -z "$CHECK_MODE" ]]; then
    echo ""
    read -p "Proceed with deployment? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
fi

# Run Ansible playbook
log_step "Running Ansible playbook..."
echo ""

cd "$ANSIBLE_DIR"

ansible-playbook \
    -i inventory/lab.yaml \
    playbooks/deploy-all.yaml \
    $CHECK_MODE \
    $TAGS \
    $SKIP_REBOOT \
    $EXTRA_ARGS

RESULT=$?

echo ""
if [[ $RESULT -eq 0 ]]; then
    log_info "=============================================="
    log_info "  Deployment Complete!"
    log_info "=============================================="
    echo ""

    if [[ -z "$CHECK_MODE" ]]; then
        # Get the lab host IP
        HOST_IP=$(grep "ansible_host:" "$INVENTORY" | head -1 | awk '{print $2}')

        echo "Access your deployment:"
        echo "  SSH:        ssh root@${HOST_IP}"
        echo "  Inference:  http://${HOST_IP}:30080"
        echo "  Health:     curl http://${HOST_IP}:30080/health"
        echo ""
        echo "Useful commands on the lab machine:"
        echo "  kubectl get pods -A"
        echo "  kubectl logs -f deployment/inference-server -n forge-cognition"
        echo "  nvidia-smi"
    fi
else
    log_error "Deployment failed with exit code: $RESULT"
    exit $RESULT
fi
