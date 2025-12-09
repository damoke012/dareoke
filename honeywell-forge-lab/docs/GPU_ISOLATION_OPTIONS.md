# GPU Isolation & Partitioning Options

## Overview

Honeywell's edge appliances need to run multiple GPU workloads:
- **LLM Inference** (main workload, highest priority)
- **Milvus Vector DB** (optional GPU acceleration)
- **Embedding Model** (if running locally)
- **Guardrails/Safety Model** (if GPU-accelerated)

This document covers isolation options for the prototype and production.

---

## Technology Comparison

| Technology | Isolation Level | Memory Isolation | Latency Impact | Supported GPUs |
|------------|-----------------|------------------|----------------|----------------|
| **MIG** | Hardware | ✅ Full | None | A100, A30, H100 only |
| **MPS** | Process | ❌ Shared | Low | Volta+ (V100, etc.) |
| **Time-Slicing** | Time | ❌ Shared | Medium | Any GPU |
| **Container Sharing** | None | ❌ Shared | Variable | Any GPU |

---

## Option 1: No Isolation (Default - Simplest)

**How it works:** All containers share the GPU. First-come-first-served for memory.

```yaml
# docker-compose.yaml
services:
  llm-inference:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

  milvus:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

**Pros:**
- Works on any GPU (including Tesla P40)
- No configuration needed
- Maximum flexibility

**Cons:**
- No memory isolation - one container can OOM others
- No guaranteed resources
- Unpredictable latency under contention

**When to use:** Development, testing, low-concurrency scenarios

---

## Option 2: Memory Limits via vLLM/TensorRT-LLM

**How it works:** Configure inference engine to use only a portion of GPU memory.

```yaml
# sku_profiles.yaml
jetson_thor:
  tensorrt_llm:
    gpu_memory_utilization: 0.70  # Use only 70% of GPU for LLM
```

```python
# vLLM configuration
from vllm import LLM
llm = LLM(
    model="...",
    gpu_memory_utilization=0.70,  # Leave 30% for other services
)
```

**Pros:**
- Works on any GPU
- Predictable memory allocation
- Other services can use remaining memory

**Cons:**
- Not enforced by hardware (soft limit)
- Doesn't prevent CUDA context overhead
- Other service must also limit itself

**Recommended allocation:**
| Service | GPU Memory |
|---------|------------|
| LLM Inference | 70-80% |
| Milvus (if GPU) | 10-15% |
| Embeddings | 5-10% |
| Buffer | 5% |

---

## Option 3: CUDA MPS (Multi-Process Service)

**How it works:** NVIDIA daemon that allows GPU sharing with better scheduling.

**Requirements:** Volta+ architecture (V100, T4, A100, etc.)
**NOT supported on:** Tesla P40 (Pascal), Jetson Thor (different architecture)

```bash
# Start MPS daemon
nvidia-cuda-mps-control -d

# Containers automatically use MPS when available
docker run --gpus all -e CUDA_MPS_PIPE_DIRECTORY=/tmp/nvidia-mps ...
```

**Pros:**
- Better GPU utilization than time-slicing
- Lower context switch overhead
- Works with multiple processes

**Cons:**
- No memory isolation
- Requires Volta+ GPU
- Not available on Jetson

---

## Option 4: Kubernetes Time-Slicing

**How it works:** NVIDIA device plugin allows fractional GPU allocation.

**Requirements:** Kubernetes with NVIDIA device plugin

```yaml
# nvidia-device-plugin-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-device-plugin-config
data:
  config.yaml: |
    version: v1
    sharing:
      timeSlicing:
        resources:
          - name: nvidia.com/gpu
            replicas: 4  # Split GPU into 4 virtual GPUs
```

```yaml
# Pod requesting 1/4 of GPU
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: llm
    resources:
      limits:
        nvidia.com/gpu: 1  # Gets 1 of 4 slices
```

**Pros:**
- Works on any GPU
- Kubernetes-native
- Fair scheduling

**Cons:**
- Time-based, not memory-based isolation
- Context switching overhead
- Increased latency variance

---

## Option 5: Run Milvus CPU-Only

**How it works:** Offload Milvus to CPU, reserve entire GPU for LLM.

**This is often the best option for edge devices with limited GPU memory.**

```yaml
# docker-compose.yaml
services:
  llm-inference:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    environment:
      - VLLM_GPU_MEMORY_UTILIZATION=0.90  # Use 90% for LLM

  milvus:
    # No GPU reservation - runs on CPU only
    environment:
      - MILVUS_GPU_SEARCH_ENABLED=false
```

**Pros:**
- LLM gets full GPU
- Milvus works fine on CPU for moderate vector sizes
- Simplest isolation

**Cons:**
- Slower vector search (acceptable for <1M vectors)
- CPU load increases

**When to use:** When LLM performance is critical and vector DB is secondary

---

## Recommended Strategy for Prototype

### Tesla P40 Lab (24GB)

```
┌─────────────────────────────────────────────────────────────┐
│                     Tesla P40 (24GB)                        │
├─────────────────────────────────────────────────────────────┤
│  vLLM/TensorRT-LLM                                         │
│  gpu_memory_utilization: 0.85 (20GB)                        │
│  - TinyLlama or Phi-2 model                                 │
│  - 10 concurrent sessions                                   │
├─────────────────────────────────────────────────────────────┤
│  Reserved for CUDA overhead + buffer (4GB)                  │
└─────────────────────────────────────────────────────────────┘

Milvus: CPU-only (no GPU allocation)
```

### Jetson Thor Production (128GB unified)

```
┌─────────────────────────────────────────────────────────────┐
│                  Jetson Thor (128GB unified)                │
├─────────────────────────────────────────────────────────────┤
│  TensorRT-LLM (LLM)                                         │
│  gpu_memory_utilization: 0.70 (~90GB)                       │
│  - Honeywell 9B model                                       │
│  - 20 concurrent sessions                                   │
├─────────────────────────────────────────────────────────────┤
│  Milvus (optional GPU)                                      │
│  10-15GB for vector search acceleration                     │
├─────────────────────────────────────────────────────────────┤
│  Embeddings + Guardrails                                    │
│  10GB                                                       │
├─────────────────────────────────────────────────────────────┤
│  System + Buffer                                            │
│  ~15GB                                                      │
└─────────────────────────────────────────────────────────────┘
```

### Blackwell RTX Pro 4000 (20GB dedicated)

```
┌─────────────────────────────────────────────────────────────┐
│               Blackwell RTX Pro 4000 (20GB)                 │
├─────────────────────────────────────────────────────────────┤
│  TensorRT-LLM (LLM)                                         │
│  gpu_memory_utilization: 0.85 (17GB)                        │
│  - Honeywell 9B model (quantized)                           │
│  - 8 concurrent sessions                                    │
├─────────────────────────────────────────────────────────────┤
│  Buffer + CUDA overhead                                     │
│  3GB                                                        │
└─────────────────────────────────────────────────────────────┘

Milvus: CPU-only (not enough VRAM)
Embeddings: CPU-only or offload to separate service
```

---

## Implementation in Prototype

### Step 1: Configure Memory Limits

Already done in `sku_profiles.yaml`:

```yaml
tensorrt_llm:
  gpu_memory_utilization: 0.85  # Adjustable per SKU
```

### Step 2: Monitor GPU Memory

Our server already exposes:
- `GET /v1/gpu/stats` - Current memory usage
- `GET /metrics` - Prometheus metrics including `forge_gpu_memory_used_bytes`

### Step 3: Add Contention Handling

Our server has session limits that prevent OOM:
- Jetson Thor: 20 sessions max
- RTX Pro: 8 sessions max
- Tesla P40: 10 sessions max

When limit reached → HTTP 503 (Service Unavailable)

---

## Questions for Honeywell

17. Does Milvus need GPU acceleration, or can it run CPU-only?
    - If CPU-only: LLM gets full GPU, simpler isolation
    - If GPU needed: Need to define memory split

18. What other GPU workloads run on the appliance?
    - Embeddings model?
    - Guardrails/safety model?
    - Any vision models?

---

## Conclusion

For the prototype on Tesla P40:
1. **No hardware isolation available** (Pascal architecture)
2. **Use software memory limits** (vLLM gpu_memory_utilization)
3. **Run Milvus on CPU** for simplicity
4. **Session limits** prevent overload

For production on Jetson Thor / RTX Pro:
1. **MPS available on RTX Pro** (Blackwell) but not Jetson
2. **Software limits** are primary mechanism
3. **Time-slicing possible** if running Kubernetes
4. **Recommend CPU for Milvus** on RTX Pro due to limited VRAM
