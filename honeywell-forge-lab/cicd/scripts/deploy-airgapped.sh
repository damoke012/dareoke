#!/bin/bash
# Honeywell Forge Cognition - Air-Gapped Deployment Script
# Deploys the inference server to an edge appliance without internet access
#
# Usage:
#   ./deploy-airgapped.sh                           # Deploy with defaults
#   ./deploy-airgapped.sh --sku jetson_thor         # Force SKU
#   ./deploy-airgapped.sh --config /path/to/config  # Custom config dir
#   ./deploy-airgapped.sh --dry-run                 # Show what would be done

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
DEPLOY_DIR="/opt/forge"
CONFIG_DIR="${BUNDLE_DIR}/configs"
FORCE_SKU=""
DRY_RUN=false
COMPOSE_FILE="docker-compose.yaml"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sku)
            FORCE_SKU="$2"
            shift 2
            ;;
        --config)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --deploy-dir)
            DEPLOY_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
  --sku SKU          Force SKU (jetson_thor, rtx_4000_pro, tesla_p40)
  --config DIR       Config directory (default: bundle/configs)
  --deploy-dir DIR   Deployment directory (default: /opt/forge)
  --dry-run          Show what would be done without executing
  -h, --help         Show this help

Examples:
  $0                           # Auto-detect SKU, deploy to /opt/forge
  $0 --sku jetson_thor         # Force Jetson Thor SKU
  $0 --dry-run                 # Preview deployment
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    log_success "Docker found: $(docker --version)"

    # Check docker-compose
    if command -v docker-compose &> /dev/null; then
        log_success "docker-compose found: $(docker-compose --version)"
        COMPOSE_CMD="docker-compose"
    elif docker compose version &> /dev/null; then
        log_success "docker compose found: $(docker compose version)"
        COMPOSE_CMD="docker compose"
    else
        log_error "docker-compose not found"
        exit 1
    fi

    # Check NVIDIA runtime
    if docker info 2>/dev/null | grep -q "nvidia"; then
        log_success "NVIDIA runtime available"
    else
        log_warn "NVIDIA runtime not detected - GPU may not be available"
    fi

    # Check nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        log_success "nvidia-smi found"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
    else
        log_warn "nvidia-smi not found - cannot verify GPU"
    fi

    # Check config files
    if [ ! -d "$CONFIG_DIR" ]; then
        log_error "Config directory not found: $CONFIG_DIR"
        exit 1
    fi
    log_success "Config directory: $CONFIG_DIR"

    # Check for required config files
    for f in docker-compose.yaml sku_profiles.yaml config.yaml; do
        if [ -f "${CONFIG_DIR}/${f}" ]; then
            log_success "Found: $f"
        else
            log_warn "Missing: $f"
        fi
    done
}

# Detect or set SKU
detect_sku() {
    if [ -n "$FORCE_SKU" ]; then
        log_info "Using forced SKU: $FORCE_SKU"
        export FORGE_SKU="$FORCE_SKU"
        return
    fi

    local arch=$(uname -m)
    log_info "Detecting SKU based on architecture: $arch"

    case $arch in
        aarch64|arm64)
            export FORGE_SKU="jetson_thor"
            log_success "Detected SKU: jetson_thor (ARM64)"
            ;;
        x86_64|amd64)
            # Try to detect GPU
            if command -v nvidia-smi &> /dev/null; then
                local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
                if [[ "$gpu_name" == *"RTX 4000"* ]]; then
                    export FORGE_SKU="rtx_4000_pro"
                    log_success "Detected SKU: rtx_4000_pro (GPU: $gpu_name)"
                elif [[ "$gpu_name" == *"P40"* ]] || [[ "$gpu_name" == *"Tesla P40"* ]]; then
                    export FORGE_SKU="tesla_p40"
                    log_success "Detected SKU: tesla_p40 (GPU: $gpu_name)"
                else
                    export FORGE_SKU="generic"
                    log_warn "Unknown GPU ($gpu_name), using generic profile"
                fi
            else
                export FORGE_SKU="generic"
                log_warn "Cannot detect GPU, using generic profile"
            fi
            ;;
        *)
            export FORGE_SKU="generic"
            log_warn "Unknown architecture, using generic profile"
            ;;
    esac
}

# Setup deployment directory
setup_deploy_dir() {
    log_info "Setting up deployment directory: $DEPLOY_DIR"

    run_cmd mkdir -p "$DEPLOY_DIR"/{config,logs,models}

    # Copy config files
    log_info "Copying configuration files..."
    run_cmd cp "${CONFIG_DIR}/docker-compose.yaml" "$DEPLOY_DIR/"
    run_cmd cp "${CONFIG_DIR}/sku_profiles.yaml" "$DEPLOY_DIR/config/"
    run_cmd cp "${CONFIG_DIR}/config.yaml" "$DEPLOY_DIR/config/"

    # Copy SKU-specific override if exists
    local sku_compose="${CONFIG_DIR}/docker-compose.${FORGE_SKU}.yaml"
    if [ -f "$sku_compose" ]; then
        run_cmd cp "$sku_compose" "$DEPLOY_DIR/"
        COMPOSE_FILE="docker-compose.yaml:docker-compose.${FORGE_SKU}.yaml"
        log_success "Using SKU override: docker-compose.${FORGE_SKU}.yaml"
    fi

    log_success "Deployment directory ready"
}

# Deploy with docker-compose
deploy() {
    log_info "Deploying Forge Cognition..."

    cd "$DEPLOY_DIR"

    # Set environment variables
    export FORGE_SKU_AUTO_DETECT=false
    export FORGE_SKU="${FORGE_SKU}"

    # Stop existing deployment if running
    if [ -f "docker-compose.yaml" ]; then
        log_info "Stopping existing deployment..."
        run_cmd $COMPOSE_CMD down --remove-orphans || true
    fi

    # Start new deployment
    log_info "Starting containers..."
    run_cmd $COMPOSE_CMD up -d

    if [ "$DRY_RUN" = false ]; then
        # Wait for health check
        log_info "Waiting for health check (up to 120s)..."
        local max_wait=120
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
                log_success "Service is healthy!"
                break
            fi
            sleep 5
            waited=$((waited + 5))
            echo -n "."
        done
        echo ""

        if [ $waited -ge $max_wait ]; then
            log_error "Health check failed after ${max_wait}s"
            log_info "Check logs with: docker logs forge-inference"
            exit 1
        fi

        # Show service info
        echo ""
        log_success "Deployment complete!"
        echo ""
        echo -e "${GREEN}Service Info:${NC}"
        curl -s http://localhost:8000/v1/sku | python3 -m json.tool 2>/dev/null || \
            curl -s http://localhost:8000/v1/sku
        echo ""
        echo -e "${GREEN}Endpoints:${NC}"
        echo "  Health:     http://localhost:8000/health"
        echo "  Chat API:   http://localhost:8000/v1/chat"
        echo "  SKU Info:   http://localhost:8000/v1/sku"
        echo "  TRT Config: http://localhost:8000/v1/tensorrt-llm/config"
        echo "  Metrics:    http://localhost:8000/metrics"
    fi
}

# Main
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Forge Cognition - Air-Gapped Deployment${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY-RUN MODE - No changes will be made${NC}"
        echo ""
    fi

    preflight_checks
    echo ""

    detect_sku
    echo ""

    setup_deploy_dir
    echo ""

    deploy
}

main "$@"
