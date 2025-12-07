# Honeywell Forge Cognition - TensorRT-LLM Inference Server
# Simulates edge deployment on constrained GPU hardware

FROM nvcr.io/nvidia/tritonserver:24.08-trtllm-python-py3

LABEL maintainer="Dario - Platform Engineer"
LABEL project="Honeywell Forge Cognition Prototype"

# Install additional dependencies
RUN pip install --no-cache-dir \
    fastapi \
    uvicorn \
    prometheus-client \
    pynvml \
    numpy

WORKDIR /app

# Copy server code
COPY server.py .
COPY config.yaml .

# Expose ports
EXPOSE 8000
EXPOSE 8001
EXPOSE 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
    CMD curl -f http://localhost:8000/health || exit 1

# Start inference server
CMD ["python", "server.py"]
