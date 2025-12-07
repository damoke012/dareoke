#!/bin/bash
# Honeywell Forge Cognition - Build Script
# Cloud-agnostic container build for any registry
#
# Usage:
#   ./scripts/build.sh                           # Build with default tag
#   ./scripts/build.sh --push                    # Build and push to registry
#   REGISTRY=myregistry.com/honeywell ./scripts/build.sh --push
#
# Environment Variables:
#   REGISTRY   - Container registry (default: local build, no registry prefix)
#   VERSION    - Image version tag (default: latest)
#   PLATFORM   - Build platform (default: auto-detect)
#                Options: linux/amd64, linux/arm64

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
REGISTRY="${REGISTRY:-}"
VERSION="${VERSION:-latest}"
PLATFORM="${PLATFORM:-}"

# Image name
if [ -n "$REGISTRY" ]; then
    IMAGE="${REGISTRY}/inference-server:${VERSION}"
else
    IMAGE="forge-inference:${VERSION}"
fi

# Detect platform if not specified
if [ -z "$PLATFORM" ]; then
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
echo "Forge Cognition Build"
echo "=============================================="
echo "Image:    $IMAGE"
echo "Platform: $PLATFORM"
echo "Context:  $PROJECT_ROOT/inference-server"
echo "=============================================="

# Build
echo "Building image..."
docker build \
    --platform "$PLATFORM" \
    -t "$IMAGE" \
    -f "$PROJECT_ROOT/inference-server/Dockerfile" \
    "$PROJECT_ROOT/inference-server"

echo "Build complete: $IMAGE"

# Push if requested
if [[ "$1" == "--push" ]]; then
    if [ -z "$REGISTRY" ]; then
        echo "Error: REGISTRY must be set to push images"
        echo "Usage: REGISTRY=your-registry.com/honeywell $0 --push"
        exit 1
    fi

    echo "Pushing to registry..."
    docker push "$IMAGE"
    echo "Push complete: $IMAGE"
fi

echo ""
echo "To run locally:"
echo "  docker run --gpus all -p 8000:8000 $IMAGE"
echo ""
echo "To deploy with docker-compose:"
echo "  cd $PROJECT_ROOT/deployment && docker-compose up -d"
