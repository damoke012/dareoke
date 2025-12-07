#!/bin/bash
# Clean up all SKU simulation containers

echo "Stopping SKU simulation containers..."
docker stop forge-jetson-sim forge-rtx-sim 2>/dev/null || true

echo "Removing containers..."
docker rm forge-jetson-sim forge-rtx-sim 2>/dev/null || true

echo "Cleanup complete."
