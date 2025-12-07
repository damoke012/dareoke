#!/bin/bash
# Simulate Jetson AGX Thor deployment on x86_64 machine
#
# This forces the container to use Jetson Thor configuration:
# - 20 concurrent sessions (vs 8 for RTX)
# - 70% memory threshold (vs 80% for RTX)
# - FP8 quantization setting (vs FP16 for RTX)
# - 100GB memory limit simulation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  SIMULATING: Jetson AGX Thor (SKU 1)"
echo "=============================================="
echo ""
echo "Real Jetson Thor specs:"
echo "  - ARM64 (aarch64)"
echo "  - 128GB unified memory"
echo "  - 100W TDP"
echo "  - NVLink available"
echo ""
echo "Simulation overrides:"
echo "  - FORGE_SKU=jetson_thor"
echo "  - Memory limit: 100GB (simulated)"
echo "  - Using x86_64 container (behavior only)"
echo "=============================================="
echo ""

# Stop any existing simulation
docker stop forge-jetson-sim 2>/dev/null || true
docker rm forge-jetson-sim 2>/dev/null || true

# Run with Jetson config
docker run -d \
    --name forge-jetson-sim \
    --gpus all \
    -p 8001:8000 \
    -e FORGE_SKU=jetson_thor \
    -e FORGE_SKU_AUTO_DETECT=false \
    -e NVIDIA_VISIBLE_DEVICES=all \
    forge-inference:latest

echo "Waiting for server to start..."
sleep 5

echo ""
echo "Jetson Thor Simulation Running!"
echo ""
echo "Access:"
echo "  API:     http://localhost:8001"
echo "  Health:  http://localhost:8001/health"
echo "  SKU:     http://localhost:8001/v1/sku"
echo ""
echo "Verify SKU config:"
curl -s http://localhost:8001/v1/sku | python3 -m json.tool 2>/dev/null || echo "(server starting...)"
echo ""
echo "Logs: docker logs -f forge-jetson-sim"
