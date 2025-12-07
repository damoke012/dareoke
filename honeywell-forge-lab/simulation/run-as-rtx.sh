#!/bin/bash
# Simulate RTX 4000 Pro deployment
#
# This forces the container to use RTX 4000 Pro configuration:
# - 8 concurrent sessions (vs 20 for Jetson)
# - 80% memory threshold (vs 70% for Jetson)
# - FP16 quantization setting
# - 16GB memory limit simulation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  SIMULATING: RTX 4000 Pro (SKU 2)"
echo "=============================================="
echo ""
echo "Real RTX 4000 Pro specs:"
echo "  - x86_64"
echo "  - 20GB dedicated VRAM"
echo "  - 130W TDP"
echo "  - No NVLink"
echo ""
echo "Simulation overrides:"
echo "  - FORGE_SKU=rtx_4000_pro"
echo "  - Memory limit: 16GB"
echo "  - Native x86_64 execution"
echo "=============================================="
echo ""

# Stop any existing simulation
docker stop forge-rtx-sim 2>/dev/null || true
docker rm forge-rtx-sim 2>/dev/null || true

# Run with RTX config
docker run -d \
    --name forge-rtx-sim \
    --gpus all \
    -p 8002:8000 \
    -e FORGE_SKU=rtx_4000_pro \
    -e FORGE_SKU_AUTO_DETECT=false \
    -e NVIDIA_VISIBLE_DEVICES=all \
    --memory=16g \
    forge-inference:latest

echo "Waiting for server to start..."
sleep 5

echo ""
echo "RTX 4000 Pro Simulation Running!"
echo ""
echo "Access:"
echo "  API:     http://localhost:8002"
echo "  Health:  http://localhost:8002/health"
echo "  SKU:     http://localhost:8002/v1/sku"
echo ""
echo "Verify SKU config:"
curl -s http://localhost:8002/v1/sku | python3 -m json.tool 2>/dev/null || echo "(server starting...)"
echo ""
echo "Logs: docker logs -f forge-rtx-sim"
