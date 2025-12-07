#!/bin/bash
# Honeywell Forge Cognition - Unified Multi-SKU Build Script
# Builds container images for both hardware SKUs:
#   - SKU 1: Jetson AGX Thor (linux/arm64)
#   - SKU 2: RTX 4000 Pro (linux/amd64)
#
# Usage:
#   ./scripts/build.sh                    # Build for current platform
#   ./scripts/build.sh --push             # Build and push to registry
#   ./scripts/build.sh --multiarch        # Build for BOTH platforms (requires buildx)
#   ./scripts/build.sh --jetson           # Build for Jetson only
#   ./scripts/build.sh --rtx              # Build for RTX only
#
# Environment Variables:
#   REGISTRY   - Container registry (required for push)
#   VERSION    - Image version tag (default: latest)
#
# Examples:
#   REGISTRY=harbor.honeywell.com/forge ./scripts/build.sh --multiarch --push
#   ./scripts/build.sh --jetson    # Local Jetson build

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
REGISTRY="${REGISTRY:-}"
VERSION="${VERSION:-latest}"
PUSH=false
MULTIARCH=false
PLATFORM=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --multiarch)
            MULTIARCH=true
            shift
            ;;
        --jetson)
            PLATFORM="linux/arm64"
            shift
            ;;
        --rtx)
            PLATFORM="linux/amd64"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Image name
if [ -n "$REGISTRY" ]; then
    IMAGE="${REGISTRY}/inference-server:${VERSION}"
else
    IMAGE="forge-inference:${VERSION}"
fi

# Auto-detect platform if not specified
if [ -z "$PLATFORM" ] && [ "$MULTIARCH" = false ]; then
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            PLATFORM="linux/amd64"
            ;;
        aarch64|arm64)
            PLATFORM="linux/arm64"
            ;;
        *)
            echo "Warning: Unknown architecture $ARCH, defaulting to amd64"
            PLATFORM="linux/amd64"
            ;;
    esac
fi

echo "=============================================="
echo "Forge Cognition Unified Build"
echo "=============================================="
echo "Image:     $IMAGE"
if [ "$MULTIARCH" = true ]; then
    echo "Platforms: linux/amd64 (RTX), linux/arm64 (Jetson)"
else
    echo "Platform:  $PLATFORM"
fi
echo "Push:      $PUSH"
echo "Context:   $PROJECT_ROOT/inference-server"
echo "=============================================="

# Multi-architecture build (requires docker buildx)
if [ "$MULTIARCH" = true ]; then
    if ! docker buildx version &> /dev/null; then
        echo "Error: docker buildx not available"
        echo "Install with: docker buildx install"
        exit 1
    fi

    # Create/use buildx builder
    BUILDER_NAME="forge-multiarch"
    if ! docker buildx inspect "$BUILDER_NAME" &> /dev/null; then
        echo "Creating buildx builder: $BUILDER_NAME"
        docker buildx create --name "$BUILDER_NAME" --use
    else
        docker buildx use "$BUILDER_NAME"
    fi

    BUILD_ARGS="--platform linux/amd64,linux/arm64"
    if [ "$PUSH" = true ]; then
        if [ -z "$REGISTRY" ]; then
            echo "Error: REGISTRY must be set for multi-arch push"
            exit 1
        fi
        BUILD_ARGS="$BUILD_ARGS --push"
    else
        # Load locally (only works for single platform)
        echo "Warning: Multi-arch without --push only builds, doesn't load locally"
        echo "Use --push with REGISTRY to store images, or build single platform"
    fi

    echo "Building multi-architecture image..."
    docker buildx build \
        $BUILD_ARGS \
        -t "$IMAGE" \
        -t "${IMAGE%:*}:${VERSION}-multiarch" \
        -f "$PROJECT_ROOT/inference-server/Dockerfile" \
        "$PROJECT_ROOT/inference-server"

    echo ""
    echo "Multi-arch build complete!"
    echo "  RTX 4000 Pro (amd64): $IMAGE"
    echo "  Jetson Thor (arm64):  $IMAGE"

else
    # Single platform build
    echo "Building for platform: $PLATFORM"
    docker build \
        --platform "$PLATFORM" \
        -t "$IMAGE" \
        -f "$PROJECT_ROOT/inference-server/Dockerfile" \
        "$PROJECT_ROOT/inference-server"

    echo "Build complete: $IMAGE"

    # Push if requested
    if [ "$PUSH" = true ]; then
        if [ -z "$REGISTRY" ]; then
            echo "Error: REGISTRY must be set to push images"
            exit 1
        fi
        echo "Pushing to registry..."
        docker push "$IMAGE"
        echo "Push complete: $IMAGE"
    fi
fi

echo ""
echo "=============================================="
echo "Deployment Commands"
echo "=============================================="
echo ""
echo "Run locally (auto-detect SKU):"
echo "  docker run --gpus all -p 8000:8000 $IMAGE"
echo ""
echo "Deploy with docker-compose:"
echo "  cd $PROJECT_ROOT/deployment"
echo "  docker-compose up -d                                    # Auto-detect"
echo "  docker-compose -f docker-compose.yaml -f docker-compose.jetson.yaml up -d  # Jetson"
echo "  docker-compose -f docker-compose.yaml -f docker-compose.rtx.yaml up -d     # RTX"
echo ""
echo "Verify SKU detection:"
echo "  curl http://localhost:8000/v1/sku"
