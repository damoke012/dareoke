#!/bin/bash
# =============================================================================
# Sync GPU Operator Images for Airgapped Environments
# =============================================================================
#
# This script downloads all images required for NVIDIA GPU Operator and:
#   1. Saves them as tar files for offline transfer
#   2. Optionally pushes them to a private registry (Harbor, etc.)
#
# Usage:
#   # Download and save as tar files
#   ./sync-gpu-images.sh --save
#
#   # Download and push to private registry
#   ./sync-gpu-images.sh --push --registry harbor.example.com/nvidia
#
#   # Load images on airgapped K3s node
#   ./sync-gpu-images.sh --load --tar-dir /path/to/images
#
#   # List all required images
#   ./sync-gpu-images.sh --list
#
# Environment Variables:
#   REGISTRY_URL      - Target registry URL (for --push)
#   REGISTRY_USER     - Registry username
#   REGISTRY_PASSWORD - Registry password
#   IMAGE_DIR         - Directory to save tar files (default: ./gpu-images)
#
# =============================================================================

set -euo pipefail

# GPU Operator version
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v25.10.1}"
DRIVER_VERSION="${DRIVER_VERSION:-580.105.08}"
UBUNTU_VERSION="${UBUNTU_VERSION:-ubuntu20.04}"

# Output directory
IMAGE_DIR="${IMAGE_DIR:-./gpu-images}"

# Registry settings
REGISTRY_URL="${REGISTRY_URL:-}"
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-}"

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

# Define all required images
declare -a GPU_IMAGES=(
    # GPU Operator
    "nvcr.io/nvidia/gpu-operator:${GPU_OPERATOR_VERSION}"

    # Driver Manager
    "nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.9.1"

    # NVIDIA Driver (for Ubuntu)
    "nvcr.io/nvidia/driver:${DRIVER_VERSION}-${UBUNTU_VERSION}"

    # Container Toolkit
    "nvcr.io/nvidia/k8s/container-toolkit:v1.18.1"

    # Device Plugin
    "nvcr.io/nvidia/k8s-device-plugin:v0.18.1"

    # DCGM Exporter (monitoring)
    "nvcr.io/nvidia/k8s/dcgm-exporter:4.4.2-4.7.0-distroless"

    # GPU Feature Discovery
    "nvcr.io/nvidia/k8s/gpu-feature-discovery:v0.18.1"

    # Node Feature Discovery
    "registry.k8s.io/nfd/node-feature-discovery:v0.18.2"

    # CUDA base images (for testing)
    "nvcr.io/nvidia/cuda:12.2.0-base-ubuntu22.04"
    "nvcr.io/nvidia/cuda:12.2.0-runtime-ubuntu22.04"
)

# Images for different driver versions
declare -A DRIVER_IMAGES=(
    ["ubuntu20.04"]="nvcr.io/nvidia/driver:${DRIVER_VERSION}-ubuntu20.04"
    ["ubuntu22.04"]="nvcr.io/nvidia/driver:${DRIVER_VERSION}-ubuntu22.04"
    ["rhel8"]="nvcr.io/nvidia/driver:${DRIVER_VERSION}-rhel8"
)

list_images() {
    log_step "Required GPU Operator Images:"
    echo ""
    for img in "${GPU_IMAGES[@]}"; do
        echo "  $img"
    done
    echo ""
    log_info "Total: ${#GPU_IMAGES[@]} images"
}

detect_container_runtime() {
    if command -v podman &> /dev/null; then
        echo "podman"
    elif command -v docker &> /dev/null; then
        echo "docker"
    else
        log_error "No container runtime found (podman or docker required)"
        exit 1
    fi
}

pull_images() {
    local runtime=$(detect_container_runtime)
    log_step "Pulling images using ${runtime}..."

    local failed=()
    for img in "${GPU_IMAGES[@]}"; do
        log_info "Pulling: $img"
        if ! $runtime pull "$img" 2>&1; then
            log_warn "Failed to pull: $img"
            failed+=("$img")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warn "Failed to pull ${#failed[@]} images:"
        for img in "${failed[@]}"; do
            echo "  - $img"
        done
    fi
}

save_images() {
    local runtime=$(detect_container_runtime)

    mkdir -p "${IMAGE_DIR}"

    log_step "Saving images to ${IMAGE_DIR}..."

    # Save all images to a single tar (more efficient)
    local all_tar="${IMAGE_DIR}/gpu-operator-images-${GPU_OPERATOR_VERSION}.tar"
    log_info "Saving all images to: $all_tar"

    $runtime save -o "$all_tar" "${GPU_IMAGES[@]}" 2>&1 || {
        log_warn "Failed to save all images together, saving individually..."

        for img in "${GPU_IMAGES[@]}"; do
            local name=$(echo "$img" | sed 's|.*/||' | sed 's/:/-/g')
            local tar_file="${IMAGE_DIR}/${name}.tar"
            log_info "Saving: $img -> $tar_file"
            $runtime save -o "$tar_file" "$img" 2>&1 || log_warn "Failed to save: $img"
        done
    }

    # Create checksum file
    log_info "Creating checksums..."
    (cd "${IMAGE_DIR}" && sha256sum *.tar > checksums.sha256)

    # Create manifest
    cat > "${IMAGE_DIR}/manifest.txt" << EOF
# GPU Operator Images Manifest
# Generated: $(date)
# GPU Operator Version: ${GPU_OPERATOR_VERSION}
# Driver Version: ${DRIVER_VERSION}

# Images included:
$(printf '%s\n' "${GPU_IMAGES[@]}")

# To load on airgapped K3s node:
#   sudo k3s ctr images import gpu-operator-images-${GPU_OPERATOR_VERSION}.tar
#
# Or for individual images:
#   for f in *.tar; do sudo k3s ctr images import "\$f"; done
EOF

    log_info "Images saved to: ${IMAGE_DIR}"
    log_info "Total size: $(du -sh "${IMAGE_DIR}" | cut -f1)"

    echo ""
    log_step "Files created:"
    ls -lh "${IMAGE_DIR}"
}

push_images() {
    if [[ -z "${REGISTRY_URL}" ]]; then
        log_error "REGISTRY_URL is required for --push"
        exit 1
    fi

    local runtime=$(detect_container_runtime)

    # Login to registry if credentials provided
    if [[ -n "${REGISTRY_USER}" && -n "${REGISTRY_PASSWORD}" ]]; then
        log_info "Logging into registry: ${REGISTRY_URL}"
        echo "${REGISTRY_PASSWORD}" | $runtime login "${REGISTRY_URL%%/*}" -u "${REGISTRY_USER}" --password-stdin
    fi

    log_step "Pushing images to ${REGISTRY_URL}..."

    for img in "${GPU_IMAGES[@]}"; do
        local src_img="$img"
        local img_name=$(echo "$img" | sed 's|.*/||')
        local dst_img="${REGISTRY_URL}/${img_name}"

        log_info "Tagging: $src_img -> $dst_img"
        $runtime tag "$src_img" "$dst_img"

        log_info "Pushing: $dst_img"
        $runtime push "$dst_img" --tls-verify=false 2>&1 || log_warn "Failed to push: $dst_img"
    done

    log_info "All images pushed to: ${REGISTRY_URL}"
}

load_images() {
    local tar_dir="${1:-${IMAGE_DIR}}"

    if [[ ! -d "$tar_dir" ]]; then
        log_error "Directory not found: $tar_dir"
        exit 1
    fi

    log_step "Loading images from ${tar_dir}..."

    # Check if we're on a K3s node
    if command -v k3s &> /dev/null; then
        for tar_file in "${tar_dir}"/*.tar; do
            if [[ -f "$tar_file" ]]; then
                log_info "Importing: $tar_file"
                sudo k3s ctr images import "$tar_file"
            fi
        done
    elif command -v ctr &> /dev/null; then
        for tar_file in "${tar_dir}"/*.tar; do
            if [[ -f "$tar_file" ]]; then
                log_info "Importing: $tar_file"
                sudo ctr -n k8s.io images import "$tar_file"
            fi
        done
    else
        local runtime=$(detect_container_runtime)
        for tar_file in "${tar_dir}"/*.tar; do
            if [[ -f "$tar_file" ]]; then
                log_info "Loading: $tar_file"
                $runtime load -i "$tar_file"
            fi
        done
    fi

    log_info "All images loaded"
}

create_k3s_registries_config() {
    local registry_url="${1:-}"

    if [[ -z "$registry_url" ]]; then
        log_error "Registry URL required"
        exit 1
    fi

    log_step "Creating K3s registries.yaml config..."

    cat << EOF
# /etc/rancher/k3s/registries.yaml
# This file configures K3s to use a private registry as a mirror

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
    # Uncomment if auth required:
    # auth:
    #   username: admin
    #   password: secret
EOF

    echo ""
    log_info "Save this to /etc/rancher/k3s/registries.yaml on each K3s node"
    log_info "Then restart K3s: sudo systemctl restart k3s (or k3s-agent)"
}

show_help() {
    cat << EOF
GPU Operator Image Sync Tool

Usage: $0 [OPTIONS]

Options:
  --list              List all required images
  --pull              Pull all images (requires internet)
  --save              Pull and save images to tar files
  --push              Pull and push to private registry
  --load [DIR]        Load images from tar files on K3s node
  --registry-config   Generate K3s registries.yaml config
  --help, -h          Show this help

Environment Variables:
  GPU_OPERATOR_VERSION  GPU Operator version (default: v25.10.1)
  DRIVER_VERSION        NVIDIA driver version (default: 580.105.08)
  IMAGE_DIR             Output directory for tar files (default: ./gpu-images)
  REGISTRY_URL          Target registry URL (for --push)
  REGISTRY_USER         Registry username
  REGISTRY_PASSWORD     Registry password

Examples:
  # List all required images
  $0 --list

  # Download and save for airgapped transfer
  $0 --save

  # Push to Harbor registry
  REGISTRY_URL=harbor.example.com/nvidia $0 --push

  # Load images on airgapped K3s node
  $0 --load /path/to/gpu-images

  # Generate K3s mirror config
  $0 --registry-config harbor.example.com
EOF
}

# Main
case "${1:-}" in
    --list)
        list_images
        ;;
    --pull)
        pull_images
        ;;
    --save)
        pull_images
        save_images
        ;;
    --push)
        pull_images
        push_images
        ;;
    --load)
        load_images "${2:-}"
        ;;
    --registry-config)
        create_k3s_registries_config "${2:-$REGISTRY_URL}"
        ;;
    --help|-h|"")
        show_help
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
