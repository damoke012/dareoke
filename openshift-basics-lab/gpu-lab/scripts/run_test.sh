#!/bin/bash
echo "=============================================="
echo "  ROSA GPU TEST JOB"
echo "=============================================="
echo "Start Time: $(date)"
echo "Pod Name: $HOSTNAME"
echo ""

echo "--- Step 1: Check GPU Availability ---"
if nvidia-smi; then
  echo ""
  echo "[SUCCESS] GPUs detected!"
else
  echo ""
  echo "[ERROR] No GPUs found or nvidia-smi failed"
  exit 1
fi

echo ""
echo "--- Step 2: GPU Memory Info ---"
nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv

echo ""
echo "--- Step 3: Running GPU Computation ---"
python3 /scripts/gpu_test.py

echo ""
echo "=============================================="
echo "  GPU TEST COMPLETED SUCCESSFULLY"
echo "=============================================="
echo "End Time: $(date)"
echo ""
