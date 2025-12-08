#!/bin/bash
# Honeywell Forge Cognition - Bundle Creator
# Creates an air-gapped deployment bundle for manual transfer
#
# Usage:
#   ./create-bundle.sh                    # Create bundle with 'latest' tag
#   ./create-bundle.sh v1.0.0             # Create bundle with specific version
#   ./create-bundle.sh v1.0.0 --include-models  # Include model files (large!)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VERSION="${1:-latest}"
INCLUDE_MODELS=false

# Parse additional args
shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --include-models)
            INCLUDE_MODELS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BUNDLE_DIR="/tmp/forge-bundle-${VERSION}"
OUTPUT_FILE="forge-cognition-bundle-${VERSION}.tar.gz"

# Registry (change for Honeywell internal)
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-forge/inference-server}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Forge Cognition - Bundle Creator${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Version:     $VERSION"
echo "Image:       $FULL_IMAGE"
echo "Output:      $OUTPUT_FILE"
echo ""

# Cleanup previous bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"/{images,configs,scripts,docs}

# Pull and export images
echo -e "${YELLOW}Exporting x86_64 image...${NC}"
docker pull --platform linux/amd64 "$FULL_IMAGE" || {
    echo -e "${RED}Failed to pull x86 image. Building locally...${NC}"
    docker buildx build --platform linux/amd64 \
        -t "$FULL_IMAGE" \
        -f "${PROJECT_ROOT}/inference-server/Dockerfile" \
        "${PROJECT_ROOT}/inference-server" \
        --load
}
docker save "$FULL_IMAGE" | gzip > "${BUNDLE_DIR}/images/forge-inference-x86.tar.gz"
echo -e "${GREEN}x86_64 image exported${NC}"

echo -e "${YELLOW}Exporting ARM64 image...${NC}"
docker pull --platform linux/arm64 "$FULL_IMAGE" || {
    echo -e "${RED}Failed to pull ARM64 image. Building locally...${NC}"
    docker buildx build --platform linux/arm64 \
        -t "$FULL_IMAGE" \
        -f "${PROJECT_ROOT}/inference-server/Dockerfile" \
        "${PROJECT_ROOT}/inference-server" \
        --load
}
docker save "$FULL_IMAGE" | gzip > "${BUNDLE_DIR}/images/forge-inference-arm64.tar.gz"
echo -e "${GREEN}ARM64 image exported${NC}"

# Copy configs
echo -e "${YELLOW}Copying configuration files...${NC}"
cp "${PROJECT_ROOT}/deployment/docker-compose.yaml" "${BUNDLE_DIR}/configs/"
cp "${PROJECT_ROOT}/deployment/docker-compose.jetson.yaml" "${BUNDLE_DIR}/configs/" 2>/dev/null || true
cp "${PROJECT_ROOT}/deployment/docker-compose.rtx.yaml" "${BUNDLE_DIR}/configs/" 2>/dev/null || true
cp "${PROJECT_ROOT}/inference-server/sku_profiles.yaml" "${BUNDLE_DIR}/configs/"
cp "${PROJECT_ROOT}/inference-server/config.yaml" "${BUNDLE_DIR}/configs/"

# Copy deployment scripts
echo -e "${YELLOW}Copying deployment scripts...${NC}"
cp "${PROJECT_ROOT}/cicd/scripts/load-images.sh" "${BUNDLE_DIR}/scripts/"
cp "${PROJECT_ROOT}/cicd/scripts/deploy-airgapped.sh" "${BUNDLE_DIR}/scripts/"
chmod +x "${BUNDLE_DIR}/scripts/"*.sh

# Copy documentation
echo -e "${YELLOW}Copying documentation...${NC}"
cp "${PROJECT_ROOT}/docs/PERFORMANCE_TUNING.md" "${BUNDLE_DIR}/docs/" 2>/dev/null || true

# Include models if requested
if [ "$INCLUDE_MODELS" = true ]; then
    echo -e "${YELLOW}Including model files (this may take a while)...${NC}"
    mkdir -p "${BUNDLE_DIR}/models"
    # Copy model files from local storage
    if [ -d "${PROJECT_ROOT}/models" ]; then
        cp -r "${PROJECT_ROOT}/models/"* "${BUNDLE_DIR}/models/" 2>/dev/null || true
    fi
    echo -e "${GREEN}Model files included${NC}"
fi

# Create manifest
cat > "${BUNDLE_DIR}/MANIFEST.md" << EOF
# Forge Cognition Air-Gapped Bundle

**Version:** ${VERSION}
**Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Git SHA:** $(git rev-parse HEAD 2>/dev/null || echo "unknown")

## Contents

\`\`\`
bundle/
├── images/
│   ├── forge-inference-x86.tar.gz     # RTX 4000 Pro (x86_64)
│   └── forge-inference-arm64.tar.gz   # Jetson Thor (ARM64)
├── configs/
│   ├── docker-compose.yaml            # Main compose file
│   ├── docker-compose.jetson.yaml     # Jetson override (if present)
│   ├── docker-compose.rtx.yaml        # RTX override (if present)
│   ├── sku_profiles.yaml              # Hardware profiles
│   └── config.yaml                    # Server config
├── scripts/
│   ├── load-images.sh                 # Load images into Docker
│   └── deploy-airgapped.sh            # Deploy to appliance
└── docs/
    └── PERFORMANCE_TUNING.md          # Performance guide
\`\`\`

## Quick Start

1. **Transfer bundle to appliance** (USB drive, SCP, etc.)

2. **Extract bundle:**
   \`\`\`bash
   tar -xzf forge-cognition-bundle-${VERSION}.tar.gz
   cd bundle
   \`\`\`

3. **Load container image:**
   \`\`\`bash
   ./scripts/load-images.sh
   \`\`\`

4. **Deploy:**
   \`\`\`bash
   ./scripts/deploy-airgapped.sh
   \`\`\`

5. **Verify:**
   \`\`\`bash
   curl http://localhost:8000/health
   curl http://localhost:8000/v1/sku
   \`\`\`

## Hardware Profiles

| SKU | Architecture | GPU Memory | Max Sessions |
|-----|--------------|------------|--------------|
| jetson_thor | ARM64 | 128GB unified | 20 |
| rtx_4000_pro | x86_64 | 20GB VRAM | 8 |
| tesla_p40 | x86_64 | 24GB VRAM | 10 |

## Troubleshooting

- **Image won't load:** Check disk space (\`df -h\`)
- **GPU not detected:** Verify nvidia-container-toolkit is installed
- **Health check fails:** Check logs with \`docker logs forge-inference\`

## Support

Contact: Platform Engineering Team
EOF

# Create README
cat > "${BUNDLE_DIR}/README.txt" << EOF
FORGE COGNITION DEPLOYMENT BUNDLE
=================================

Version: ${VERSION}

QUICK START:
  1. ./scripts/load-images.sh
  2. ./scripts/deploy-airgapped.sh
  3. curl http://localhost:8000/health

See MANIFEST.md for full documentation.
EOF

# Create the bundle archive
echo -e "${YELLOW}Creating bundle archive...${NC}"
cd /tmp
tar -czvf "${OUTPUT_FILE}" "forge-bundle-${VERSION}"

# Move to current directory
mv "/tmp/${OUTPUT_FILE}" "${SCRIPT_DIR}/../bundles/" 2>/dev/null || \
    mv "/tmp/${OUTPUT_FILE}" "$(pwd)/"

# Show summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bundle created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Output: ${OUTPUT_FILE}"
echo "Size: $(ls -lh "${SCRIPT_DIR}/../bundles/${OUTPUT_FILE}" 2>/dev/null | awk '{print $5}' || ls -lh "${OUTPUT_FILE}" | awk '{print $5}')"
echo ""
echo "Transfer this file to your target appliance and follow"
echo "the instructions in MANIFEST.md"
