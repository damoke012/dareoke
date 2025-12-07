# Lab Exercise: GPU Inference with SKU Detection

**Duration:** 30-45 minutes
**Prerequisites:** Working GPU node (your Tesla P40 once power cable is connected)
**Goal:** Practice the same patterns used in Honeywell Forge Cognition

---

## Overview

This exercise simulates what you'll be doing at Honeywell:
1. Build a GPU-enabled container
2. Deploy with automatic hardware detection
3. Monitor GPU metrics
4. Run inference load tests

Your Tesla P40 will stand in for both Honeywell SKUs (it's x86_64 like the RTX 4000 Pro).

---

## Part 1: Understanding Your Hardware

### Step 1.1: Check GPU Details

SSH to your GPU node and gather info:

```bash
# On ocp-w-1.lab.ocp.lan (once GPU is working)
ssh core@ocp-w-1.lab.ocp.lan

# Get GPU info
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
# Expected: Tesla P40, 24576 MiB, 535.xxx

# Check architecture
uname -m
# Expected: x86_64

# Check CUDA version
nvidia-smi | grep "CUDA Version"
# Expected: CUDA Version: 12.x
```

### Step 1.2: Compare to Honeywell SKUs

| Your Lab | Jetson Thor | RTX 4000 Pro |
|----------|-------------|--------------|
| Tesla P40 | Jetson Thor | RTX 4000 Ada |
| 24GB VRAM | 128GB unified | 20GB VRAM |
| x86_64 | ARM64 | x86_64 |
| Pascal arch | Blackwell | Ada Lovelace |

**Key insight:** Your P40 is closest to RTX 4000 Pro (x86_64, dedicated VRAM).

---

## Part 2: Build and Run the Inference Server

### Step 2.1: Build for Your Platform

On your local machine or directly on the GPU node:

```bash
# Clone if needed
cd /workspaces/dareoke/honeywell-forge-lab

# Build for x86_64 (your P40)
./scripts/build.sh --rtx

# Verify image created
docker images | grep forge-inference
```

### Step 2.2: Run with GPU Access

```bash
# Run the container
docker run -d \
  --name forge-test \
  --gpus all \
  -p 8000:8000 \
  -e FORGE_SKU=generic \
  forge-inference:latest

# Check logs
docker logs -f forge-test
```

Expected output:
```
Auto-detected SKU: generic
Configuration loaded for SKU: generic
  Max concurrent sessions: 4
  Memory threshold: 90%
  Target TTFT: 200ms
Starting Forge Cognition Inference Server...
```

### Step 2.3: Verify SKU Detection

```bash
# Check what SKU was detected
curl -s http://localhost:8000/v1/sku | jq .

# Expected:
{
  "sku_name": "generic",
  "sku_description": "Generic GPU - Development/Testing",
  "architecture": "x86_64",
  "applied_config": {
    "max_concurrent_sessions": 4,
    "gpu_memory_threshold": 0.9,
    ...
  },
  "gpu_info": [
    {
      "gpu_id": 0,
      "name": "Tesla P40",
      "memory_total_gb": 24.0,
      ...
    }
  ]
}
```

---

## Part 3: Add Your GPU to SKU Profiles

### Step 3.1: Create a P40 Profile

Edit `inference-server/sku_profiles.yaml` and add:

```yaml
# Your lab GPU profile
tesla_p40:
  description: "NVIDIA Tesla P40 - Lab/Dev Environment"
  detection:
    architecture: "x86_64"
    gpu_patterns:
      - "Tesla P40"
      - "P40"

  hardware:
    gpu_memory_gb: 24
    gpu_memory_type: "dedicated"
    tdp_watts: 250
    nvlink_available: false

  inference:
    max_concurrent_sessions: 10
    max_batch_size: 8
    kv_cache_gb: 10
    quantization: "FP16"

  optimization:
    tensor_parallel: 1
    pipeline_parallel: 1
    use_paged_attention: true
    use_inflight_batching: true

  thresholds:
    memory_warning_percent: 75
    memory_critical_percent: 85
    target_ttft_ms: 150
    target_tps: 40
```

### Step 3.2: Update Detection Logic

Edit `inference-server/server.py`, in `detect_sku()` function, add:

```python
if "Tesla P40" in gpu_name or "P40" in gpu_name:
    return "tesla_p40"
```

### Step 3.3: Rebuild and Test

```bash
# Stop old container
docker stop forge-test && docker rm forge-test

# Rebuild
./scripts/build.sh --rtx

# Run again
docker run -d --name forge-test --gpus all -p 8000:8000 forge-inference:latest

# Check SKU detection
curl -s http://localhost:8000/v1/sku | jq .sku_name
# Should now show: "tesla_p40"
```

---

## Part 4: Run Inference Load Test

### Step 4.1: Create a Session

```bash
# Create inference session
curl -s -X POST http://localhost:8000/v1/sessions | jq .
# Returns: {"session_id": "abc123"}
```

### Step 4.2: Send Inference Requests

```bash
# Single request
curl -s -X POST http://localhost:8000/v1/chat \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What maintenance is needed for an HVAC compressor showing high discharge temperature?",
    "max_tokens": 256
  }' | jq .

# Check metrics
curl -s http://localhost:8000/v1/gpu/stats | jq .
```

### Step 4.3: Run Concurrent Load

Install locust and run load test:

```bash
# Install locust
pip install locust

# Run load test (from honeywell-forge-lab directory)
cd /workspaces/dareoke/honeywell-forge-lab
locust -f load-testing/locustfile.py --headless -u 5 -r 1 -t 60s --host=http://localhost:8000
```

Watch GPU memory climb as sessions increase.

---

## Part 5: Monitor with Prometheus/Grafana

### Step 5.1: Deploy Full Stack

```bash
cd /workspaces/dareoke/honeywell-forge-lab/deployment

# Stop standalone container
docker stop forge-test && docker rm forge-test

# Deploy with monitoring
docker-compose up -d
```

### Step 5.2: Access Dashboards

- **Inference API:** http://localhost:8000/health
- **Prometheus:** http://localhost:9091
- **Grafana:** http://localhost:3000 (admin/admin)

### Step 5.3: Query Metrics

In Prometheus (http://localhost:9091), try these queries:

```promql
# GPU memory usage
forge_gpu_memory_used_bytes / forge_gpu_memory_total_bytes * 100

# Time to first token (P90)
histogram_quantile(0.9, rate(forge_ttft_seconds_bucket[5m]))

# Tokens per second
rate(forge_inference_requests_total[1m])

# Active sessions
forge_active_sessions
```

---

## Part 6: Simulate SKU Switching

### Step 6.1: Override SKU Detection

Test how the server behaves with different SKU configs:

```bash
# Stop current
docker-compose down

# Run as if it were Jetson Thor
FORGE_SKU=jetson_thor docker-compose up -d

# Check applied config
curl -s http://localhost:8000/v1/sku | jq .applied_config
# Should show: max_concurrent_sessions: 20, memory_threshold: 0.85
```

### Step 6.2: Compare Behavior

```bash
# Run as RTX 4000 Pro
docker-compose down
FORGE_SKU=rtx_4000_pro docker-compose up -d

curl -s http://localhost:8000/v1/sku | jq .applied_config
# Should show: max_concurrent_sessions: 8, memory_threshold: 0.9
```

This simulates deploying the same container to different Honeywell appliances.

---

## Part 7: Cleanup

```bash
cd /workspaces/dareoke/honeywell-forge-lab/deployment
docker-compose down -v

# Remove images if needed
docker rmi forge-inference:latest
```

---

## Key Learnings

After this exercise, you should understand:

1. **SKU auto-detection** - How the container identifies hardware at runtime
2. **Profile-based config** - Same container, different settings per hardware
3. **GPU resource monitoring** - Memory, utilization, temperature tracking
4. **Inference metrics** - TTFT, TPS, latency histograms
5. **Load testing** - How concurrent sessions affect performance
6. **Docker GPU runtime** - `--gpus all` and nvidia container toolkit

---

## Relation to Honeywell Project

| Lab Exercise | Honeywell Week |
|--------------|----------------|
| Build container | Week 1 - Deployment automation |
| SKU detection | Week 1 - Hardware validation |
| Load testing | Week 5-6 - Stress testing |
| Monitoring setup | Week 2-3 - GPU resource planning |
| Profile tuning | Week 4 - Memory optimization |

---

## Next Steps

Once your Tesla P40 power cable arrives:
1. Connect the cable
2. Re-enable GPU: `oc label node ocp-w-1.lab.ocp.lan nvidia.com/gpu.deploy.operands-`
3. Run this exercise on OpenShift instead of Docker
4. Use the GPU Operator to manage driver lifecycle

---

*Created: December 7, 2025*
