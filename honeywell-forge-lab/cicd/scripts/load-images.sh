#!/bin/bash
# Honeywell Forge Cognition - Air-Gapped Image Loader
# Loads container images from bundle into local Docker daemon
#
# Usage:
#   ./load-images.sh                    # Auto-detect architecture
#   ./load-images.sh --arch arm64       # Force ARM64 (Jetson)
#   ./load-images.sh --arch amd64       # Force x86 (RTX)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="${BUNDLE_DIR}/images"

# Parse arguments
FORCE_ARCH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            FORCE_ARCH="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--arch arm64|amd64]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

ARCH="${FORCE_ARCH:-$(detect_arch)}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Forge Cognition - Image Loader${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Architecture: ${YELLOW}${ARCH}${NC}"
echo -e "Bundle dir:   ${YELLOW}${BUNDLE_DIR}${NC}"
echo ""

# Check if images directory exists
if [ ! -d "$IMAGES_DIR" ]; then
    echo -e "${RED}Error: Images directory not found at ${IMAGES_DIR}${NC}"
    echo "Make sure you're running this from the bundle directory"
    exit 1
fi

# Select correct image based on architecture
case $ARCH in
    amd64)
        IMAGE_FILE="${IMAGES_DIR}/forge-inference-x86.tar.gz"
        ;;
    arm64)
        IMAGE_FILE="${IMAGES_DIR}/forge-inference-arm64.tar.gz"
        ;;
    *)
        echo -e "${RED}Error: Unknown architecture: ${ARCH}${NC}"
        exit 1
        ;;
esac

# Check if image file exists
if [ ! -f "$IMAGE_FILE" ]; then
    echo -e "${RED}Error: Image file not found: ${IMAGE_FILE}${NC}"
    exit 1
fi

# Load the image
echo -e "${YELLOW}Loading image from ${IMAGE_FILE}...${NC}"
echo "This may take a few minutes..."
echo ""

if gunzip -c "$IMAGE_FILE" | docker load; then
    echo ""
    echo -e "${GREEN}Image loaded successfully!${NC}"
else
    echo -e "${RED}Failed to load image${NC}"
    exit 1
fi

# Show loaded image
echo ""
echo -e "${GREEN}Loaded images:${NC}"
docker images | grep forge-inference || echo "No forge-inference images found"

echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Copy configs: cp ${BUNDLE_DIR}/configs/* /opt/forge/"
echo "2. Run deployment: ./deploy-airgapped.sh"
