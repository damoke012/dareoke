#!/bin/bash
# Run BOTH SKU simulations side-by-side and compare behavior
#
# This demonstrates how the same container image behaves differently
# based on detected/configured SKU - the core of unified deployment.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  DUAL-SKU COMPARISON TEST"
echo "=============================================="
echo ""
echo "This runs both SKU configurations simultaneously"
echo "to demonstrate unified deployment behavior."
echo ""
echo "Ports:"
echo "  - Jetson Thor: localhost:8001"
echo "  - RTX 4000:    localhost:8002"
echo "=============================================="
echo ""

# Build if not exists
if ! docker images | grep -q "forge-inference"; then
    echo "Building container image..."
    cd "$(dirname "$SCRIPT_DIR")"
    ./scripts/build.sh
fi

# Stop any existing
echo "Cleaning up previous runs..."
docker stop forge-jetson-sim forge-rtx-sim 2>/dev/null || true
docker rm forge-jetson-sim forge-rtx-sim 2>/dev/null || true

# Start both
echo ""
echo "Starting Jetson Thor simulation (port 8001)..."
docker run -d \
    --name forge-jetson-sim \
    --gpus all \
    -p 8001:8000 \
    -e FORGE_SKU=jetson_thor \
    -e FORGE_SKU_AUTO_DETECT=false \
    forge-inference:latest

echo "Starting RTX 4000 Pro simulation (port 8002)..."
docker run -d \
    --name forge-rtx-sim \
    --gpus all \
    -p 8002:8000 \
    -e FORGE_SKU=rtx_4000_pro \
    -e FORGE_SKU_AUTO_DETECT=false \
    --memory=16g \
    forge-inference:latest

echo ""
echo "Waiting for servers to initialize..."
sleep 8

echo ""
echo "=============================================="
echo "  CONFIGURATION COMPARISON"
echo "=============================================="
echo ""

# Fetch and compare configs
echo "┌─────────────────────────────────────────────────────────────────────────┐"
echo "│                         SKU CONFIGURATION COMPARISON                      │"
echo "├────────────────────────┬─────────────────────┬─────────────────────────┤"
echo "│ Setting                │ Jetson Thor (8001)  │ RTX 4000 Pro (8002)     │"
echo "├────────────────────────┼─────────────────────┼─────────────────────────┤"

# Get configs
JETSON_CONFIG=$(curl -s http://localhost:8001/v1/sku 2>/dev/null || echo '{}')
RTX_CONFIG=$(curl -s http://localhost:8002/v1/sku 2>/dev/null || echo '{}')

# Extract values
JETSON_SESSIONS=$(echo "$JETSON_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('max_concurrent_sessions','N/A'))" 2>/dev/null || echo "N/A")
RTX_SESSIONS=$(echo "$RTX_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('max_concurrent_sessions','N/A'))" 2>/dev/null || echo "N/A")

JETSON_THRESH=$(echo "$JETSON_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('gpu_memory_threshold','N/A'))" 2>/dev/null || echo "N/A")
RTX_THRESH=$(echo "$RTX_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('gpu_memory_threshold','N/A'))" 2>/dev/null || echo "N/A")

JETSON_TTFT=$(echo "$JETSON_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('target_ttft_ms','N/A'))" 2>/dev/null || echo "N/A")
RTX_TTFT=$(echo "$RTX_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('target_ttft_ms','N/A'))" 2>/dev/null || echo "N/A")

JETSON_QUANT=$(echo "$JETSON_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('quantization','N/A'))" 2>/dev/null || echo "N/A")
RTX_QUANT=$(echo "$RTX_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin).get('applied_config',{}).get('quantization','N/A'))" 2>/dev/null || echo "N/A")

printf "│ %-22s │ %-19s │ %-23s │\n" "Max Sessions" "$JETSON_SESSIONS" "$RTX_SESSIONS"
printf "│ %-22s │ %-19s │ %-23s │\n" "Memory Threshold" "$JETSON_THRESH" "$RTX_THRESH"
printf "│ %-22s │ %-19s │ %-23s │\n" "Target TTFT (ms)" "$JETSON_TTFT" "$RTX_TTFT"
printf "│ %-22s │ %-19s │ %-23s │\n" "Quantization" "$JETSON_QUANT" "$RTX_QUANT"
echo "└────────────────────────┴─────────────────────┴─────────────────────────┘"

echo ""
echo "=============================================="
echo "  BEHAVIORAL TEST"
echo "=============================================="
echo ""

# Test session limits
echo "Testing session creation limits..."
echo ""

echo "Jetson Thor (should allow 20 sessions):"
for i in {1..5}; do
    RESULT=$(curl -s -X POST http://localhost:8001/v1/sessions 2>/dev/null)
    echo "  Session $i: $(echo $RESULT | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','error'))" 2>/dev/null || echo 'error')"
done

echo ""
echo "RTX 4000 Pro (should allow 8 sessions):"
for i in {1..5}; do
    RESULT=$(curl -s -X POST http://localhost:8002/v1/sessions 2>/dev/null)
    echo "  Session $i: $(echo $RESULT | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id','error'))" 2>/dev/null || echo 'error')"
done

echo ""
echo "=============================================="
echo "  FULL SKU INFO"
echo "=============================================="
echo ""
echo "Jetson Thor (/v1/sku):"
curl -s http://localhost:8001/v1/sku 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(unavailable)"
echo ""
echo "RTX 4000 Pro (/v1/sku):"
curl -s http://localhost:8002/v1/sku 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(unavailable)"

echo ""
echo "=============================================="
echo "  CLEANUP COMMANDS"
echo "=============================================="
echo ""
echo "To stop simulations:"
echo "  docker stop forge-jetson-sim forge-rtx-sim"
echo "  docker rm forge-jetson-sim forge-rtx-sim"
echo ""
echo "Or run: $SCRIPT_DIR/cleanup.sh"
