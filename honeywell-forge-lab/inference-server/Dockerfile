# Honeywell Forge Cognition - Unified Multi-SKU Inference Server
# Supports both hardware SKUs:
#   - SKU 1: Jetson AGX Thor (ARM64, 128GB unified memory)
#   - SKU 2: RTX 4000 Pro (x86_64, ~20GB VRAM)
#
# Build for specific platform:
#   docker build --build-arg TARGETARCH=amd64 -t forge-inference:x86 .
#   docker build --build-arg TARGETARCH=arm64 -t forge-inference:jetson .
#
# Multi-platform build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t forge-inference:latest .

ARG TARGETARCH=amd64

# ============================================================================
# Base image selection based on architecture
# ============================================================================
# x86_64 (RTX 4000 Pro): Use standard TensorRT-LLM image
# ARM64 (Jetson Thor): Use L4T-based image with JetPack
FROM nvcr.io/nvidia/tritonserver:24.08-trtllm-python-py3 AS base-amd64
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0 AS base-arm64

# Select the correct base
FROM base-${TARGETARCH} AS runtime

LABEL maintainer="Dario - Platform Engineer"
LABEL project="Honeywell Forge Cognition"
LABEL description="Unified inference server for dual-SKU deployment"

# ============================================================================
# Install dependencies
# ============================================================================
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    prometheus-client \
    pynvml \
    numpy \
    pyyaml

WORKDIR /app

# Copy server code and configs
COPY server.py .
COPY config.yaml .
COPY sku_profiles.yaml .

# Expose ports
EXPOSE 8000   # HTTP API
EXPOSE 8001   # gRPC (if needed)
EXPOSE 9090   # Metrics

# Environment variables for SKU auto-detection
ENV FORGE_SKU_AUTO_DETECT=true
ENV FORGE_CONFIG_PATH=/app/config.yaml

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s \
    CMD curl -f http://localhost:8000/health || exit 1

# Start inference server
CMD ["python", "server.py"]
