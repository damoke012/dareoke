# Forge Cognition Lab - Setup Guide

## Prerequisites

- Docker with NVIDIA runtime
- Python 3.10+
- Access to GPU (Tesla P40 or similar for testing)
- OpenShift/Kubernetes cluster (optional, for full deployment)

## Quick Start (Local Docker)

### 1. Build the Inference Server

```bash
cd honeywell-forge-lab/inference-server

# Build image
docker build -t forge-inference:latest .
```

### 2. Run with GPU

```bash
# Run inference server
docker run --gpus all -p 8000:8000 forge-inference:latest

# Verify health
curl http://localhost:8000/health
```

### 3. Test Inference

```bash
# Create session
curl -X POST http://localhost:8000/v1/sessions

# Make inference request
curl -X POST http://localhost:8000/v1/chat \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the maintenance schedule for HVAC unit AHU-001?",
    "max_tokens": 256
  }'
```

## Running Benchmarks

### Install Dependencies

```bash
pip install aiohttp locust pynvml numpy
```

### Run Inference Benchmark

```bash
cd benchmarks

# Quick benchmark
python benchmark_inference.py --host http://localhost:8000 --quick

# Full benchmark with output
python benchmark_inference.py --host http://localhost:8000 --output results/
```

### Run Memory Profiler

```bash
# Profile memory usage vs sessions
python memory_profiler.py --host http://localhost:8000 --max-sessions 15
```

### Run Load Test

```bash
cd load-testing

# Web UI (interactive)
locust -f locustfile.py --host=http://localhost:8000

# Headless (CI/CD)
locust -f locustfile.py --host=http://localhost:8000 \
       --headless -u 10 -r 2 -t 60s --csv=results/load_test
```

## GPU Monitoring

```bash
cd monitoring

# Live GPU metrics
python gpu-metrics.py

# Export to CSV
python gpu-metrics.py --export results/ --duration 300
```

## OpenShift Deployment

```bash
# Ensure you're logged in
oc whoami

# Create project (if needed)
oc new-project forge-cognition-lab

# Deploy
oc apply -f deployment/

# Check status
oc get pods -l app=forge-inference

# Get route
oc get route forge-inference
```

## Metrics Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /health` | Health check with GPU stats |
| `GET /metrics` | Prometheus metrics |
| `GET /v1/gpu/stats` | Detailed GPU statistics |
| `GET /v1/sessions` | Active session list |
| `GET /v1/config` | Server configuration |

## Key Metrics to Track

### Time to First Token (TTFT)
- Target: P90 < 100ms
- Critical: P90 > 500ms

### Tokens Per Second (TPS)
- Target: > 50 tokens/sec
- Minimum: > 20 tokens/sec

### Concurrent Sessions
- RTX 4000 Pro: 5-8 sessions
- Jetson Thor: 15-20 sessions

### GPU Memory
- Warning: > 80%
- Critical: > 90%

## Troubleshooting

### GPU Not Detected

```bash
# Check NVIDIA driver
nvidia-smi

# Check Docker GPU support
docker run --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### High Latency

1. Check GPU utilization (`/v1/gpu/stats`)
2. Reduce concurrent sessions
3. Check for memory pressure

### Out of Memory

1. Reduce `max_concurrent_sessions` in config
2. Reduce `max_tokens` per request
3. Consider model quantization
