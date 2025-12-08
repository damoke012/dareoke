# Complete Meeting Analysis - December 8, 2025

## Executive Summary

Two meetings covered the Honeywell Forge Cognition project. Here's what we now know:

### The Core Problem
**85-second latency** at 20 concurrent users on Jetson AGX Thor (128GB shared memory). This is unacceptable for a chatbot experience.

### Root Causes Identified
1. **KV Cache in FP32** - Using ~45-50GB for 20k token context
2. **GPU Resource Contention** - LLM, Embeddings, Milvus Vector Search all fighting for GPU
3. **Massive Input Context** - 20,000 tokens (mostly RAG retrieved docs)
4. **No Backend Optimization** - Using vLLM (or nothing), not TensorRT-LLM
5. **CUDA Errors** - Random crashes in embedding models due to memory pressure

### The Two Hardware SKUs
| SKU | Memory | Challenge |
|-----|--------|-----------|
| **Jetson AGX Thor** | 128GB unified (shared CPU/GPU) | Memory contention with OS/services |
| **RTX Pro 4000** | 24GB dedicated | Cannot fit current 50GB workload at all |

---

## Detailed Analysis

### 1. Architecture Understanding

```
┌─────────────────────────────────────────────────────────────────────┐
│                    MAINTENANCE ASSIST (MA) FLOW                      │
│                                                                      │
│  User Query                                                          │
│      │                                                               │
│      ▼                                                               │
│  ┌─────────────┐                                                    │
│  │  Chat API   │                                                    │
│  └──────┬──────┘                                                    │
│         │                                                            │
│         ▼                                                            │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              LangChain Agent (ReAct Loop)                    │   │
│  │                                                               │   │
│  │  1. Look at question + history + tools                       │   │
│  │  2. Decide: Answer OR Use Tool                               │   │
│  │  3. If tool → invoke → get result → loop back to step 1      │   │
│  │  4. If answer → stream response                              │   │
│  └─────────────────────────────────────────────────────────────┘   │
│         │                           │                                │
│         ▼                           ▼                                │
│  ┌─────────────┐           ┌─────────────────┐                     │
│  │  Retriever  │           │  Data Access    │                     │
│  │  (RAG)      │           │  API (BMS)      │                     │
│  └──────┬──────┘           └─────────────────┘                     │
│         │                                                            │
│         ▼                                                            │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Milvus Vector DB                          │   │
│  │                 (GPU-accelerated search)                      │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  MODELS RUNNING CONCURRENTLY:                                       │
│  • LLM: Nemotron SLM (~9B params) - FP4 weights, FP32 KV cache     │
│  • Embedding Model: For query vectorization                         │
│  • Reranker Model: For retrieval ranking                           │
│  • Milvus: GPU-accelerated vector search                           │
│  • (Optional) Guardrails: Separate LLM for safety filtering        │
└─────────────────────────────────────────────────────────────────────┘
```

### 2. The Memory Problem (Critical)

**Current State on Jetson Thor:**
```
Total Memory:           128 GB (unified)
─────────────────────────────────────────
OS + Core Services:      ~10-20 GB (estimate)
LLM Weights (FP4):       ~5 GB
KV Cache (FP32!):        ~45 GB  ← SMOKING GUN
Embedding Model:         ~2-4 GB
Reranker:                ~1-2 GB
Milvus GPU Memory:       ~5-10 GB
─────────────────────────────────────────
Total Used:              ~70-85 GB

Remaining for concurrency: ~40-55 GB
Per additional user KV:    ~2-4 GB
Max concurrent users:      ~10-20 (barely)
```

**The Fix:** FP8 KV Cache would reduce 45GB → ~11GB, freeing ~34GB

### 3. The Latency Breakdown

**85 seconds for 20 concurrent users with 20k input tokens**

| Stage | Estimated Time | Bottleneck |
|-------|---------------|------------|
| Query embedding | ~100ms | Minor |
| Vector search (Milvus) | ~500ms-2s | GPU contention |
| LLM Prefill (20k tokens) | **30-60s** | MAJOR - attention O(n²) |
| LLM Decode (500 tokens) | ~10-20s | KV cache memory |
| Guardrails (if separate) | ~5-10s | Second LLM pass |
| **Total** | **~85s** | |

### 4. What They're Using vs What They Need

| Component | Current | Recommended |
|-----------|---------|-------------|
| LLM Backend | vLLM (maybe) | TensorRT-LLM |
| Model | Nemotron 9B | Same or smaller |
| Weights | FP4 | FP4/FP8 |
| KV Cache | **FP32** | **FP8** |
| Attention | Standard | Paged Attention |
| Batching | Unknown | In-flight Batching |
| Vector Search | Milvus GPU | Milvus CPU (offload) |
| Guardrails | Separate 9B LLM | Lightweight classifier |

### 5. The RTX 4000 Problem

**Current workload needs 50GB+. RTX 4000 only has 24GB.**

Options discussed:
- **A) Context Pruning:** Limit RTX to 4-8k tokens (vs 20k on Thor)
- **B) Model Distillation:** Smaller model (4B-7B) for RTX
- **C) Aggressive Quantization:** 4-bit everything including KV cache

**Reality:** RTX will be a "lite" version with fewer capabilities.

---

## What We Need to Build

### Phase 1: Optimized Single-User Pipeline
1. TensorRT-LLM backend setup
2. FP8 KV cache implementation
3. Paged attention enabled
4. Benchmark single user latency

### Phase 2: Concurrency Optimization
1. In-flight batching configuration
2. Memory profiling per concurrent user
3. Milvus CPU offload testing
4. Max concurrency benchmarking

### Phase 3: Unified Deployment
1. Single container that works on both SKUs
2. SKU auto-detection and configuration
3. Different limits per SKU (sessions, context)
4. Deployment automation

---

## Prototype Plan

### What We Already Have (Our Prep Work)
✅ Multi-arch Dockerfile (Jetson ARM64 + RTX x86_64)
✅ SKU auto-detection
✅ SKU profiles with different limits
✅ Docker Compose deployment
✅ Monitoring stack (Prometheus/Grafana)
✅ Load testing scripts

### What We Need to Add

#### 1. TensorRT-LLM Integration
```python
# Replace simulated inference with TensorRT-LLM
from tensorrt_llm import LLM
from tensorrt_llm.hlapi import SamplingParams

class TRTLLMInferenceEngine:
    def __init__(self, model_path: str, config: SKUConfig):
        self.llm = LLM(
            model=model_path,
            tensor_parallel_size=1,
            kv_cache_config={
                "enable_block_reuse": True,
                "dtype": "fp8"  # KEY: FP8 KV cache
            }
        )
        self.max_tokens = config.max_tokens

    async def generate(self, prompt: str, session_id: str):
        params = SamplingParams(
            max_tokens=self.max_tokens,
            temperature=0.7
        )
        # Uses paged attention automatically
        output = self.llm.generate(prompt, params)
        return output
```

#### 2. Memory Monitoring Additions
```yaml
# Add to sku_profiles.yaml
jetson_thor:
  memory:
    total_gb: 128
    reserved_for_os_gb: 20
    reserved_for_milvus_gb: 10
    available_for_inference_gb: 98
    kv_cache_per_session_gb: 2  # With FP8

rtx_4000_pro:
  memory:
    total_gb: 24
    reserved_for_milvus_gb: 4
    available_for_inference_gb: 20
    kv_cache_per_session_gb: 1.5  # With FP8, smaller context
```

#### 3. Milvus CPU Offload Option
```yaml
# docker-compose.yaml addition
services:
  milvus:
    image: milvusdb/milvus:latest
    environment:
      # CPU-only mode to free GPU for LLM
      - MILVUS_GPU_SEARCH_ENABLED=false
      - MILVUS_USE_GPU=false
```

---

## Testing on Client System

### Pre-Deployment Checklist
1. **Verify hardware access** - SSH to Thor and RTX devices
2. **Check GPU stack** - Driver, CUDA, TensorRT versions
3. **Baseline benchmark** - Current latency/memory before changes
4. **Container runtime** - Docker + nvidia-container-toolkit

### Test Sequence

#### Test 1: Single User Latency
```bash
# Deploy optimized container
./scripts/deploy.sh docker

# Run single user test
curl -X POST http://localhost:8000/v1/chat \
  -d '{"prompt": "20k token context here...", "max_tokens": 500}'

# Measure:
# - Time to First Token (TTFT)
# - Total latency
# - GPU memory usage
```

#### Test 2: Concurrency Scaling
```bash
# Run load test with increasing users
for users in 1 5 10 15 20; do
  python load-testing/locustfile.py --users $users --duration 60s
  # Record: latency, memory, errors
done
```

#### Test 3: Memory Profiling
```bash
# Monitor during load test
watch -n 1 'nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv'

# Or use our GPU metrics script
python monitoring/gpu-metrics.py --export results/
```

#### Test 4: KV Cache Comparison
```bash
# Test FP32 vs FP8 KV cache
FORGE_KV_CACHE_DTYPE=fp32 ./scripts/deploy.sh docker
# Benchmark...

FORGE_KV_CACHE_DTYPE=fp8 ./scripts/deploy.sh docker
# Benchmark...

# Compare memory usage and latency
```

---

## SOW Achievement Plan

### SOW Deliverables Mapping

| SOW Requirement | Our Deliverable | Status |
|-----------------|-----------------|--------|
| Unified deployment for both SKUs | Multi-arch container + SKU detection | ✅ Ready |
| TensorRT-LLM optimization | Container with TRT-LLM backend | 🔄 Need integration |
| KV cache optimization | FP8 KV cache config | 🔄 Need client testing |
| Automated deployment scripts | build.sh, deploy.sh, docker-compose | ✅ Ready |
| GPU resource optimization | Milvus CPU offload, memory profiling | 🔄 Need benchmarks |
| Performance benchmarking | Load test scripts, metrics export | ✅ Ready |
| Failover/recovery | K3s option documented | ⏳ If needed |

### Week-by-Week Plan

**Week 1-2: Foundation**
- Get hardware access
- Deploy baseline, collect metrics
- Implement TensorRT-LLM backend
- Test FP8 KV cache

**Week 3-4: Optimization**
- Tune for single-user latency target
- Milvus CPU offload testing
- Memory profiling and limits

**Week 5-6: Concurrency**
- In-flight batching tuning
- Max concurrent user testing
- SKU-specific limit validation

**Week 7-8: Unified Deployment**
- Test on both Thor and RTX
- Validate SKU auto-detection
- Document differences

**Week 9-10: Stress Testing**
- Extended load tests
- Failure injection
- Recovery testing

**Week 11-12: Handoff**
- Documentation
- Training
- Production deployment support

---

## Key Contacts from Meetings

| Name | Role | Notes |
|------|------|-------|
| Nishant | Tech Lead | Primary contact for architecture questions |
| Pawan | Client side | Showed MA architecture |
| Swamil | Engagement | Coordination |
| Matab, Rishika | Developers | TensorRT-LLM implementation |
| Atalia | Nvidia contact | For Nvidia-specific issues |
| Bala, Vishal | Architects | Architecture decisions |

---

## Critical Questions Answered by Meetings

| Question | Answer from Meeting |
|----------|---------------------|
| What's causing 85s latency? | 20k token prefill + FP32 KV cache + GPU contention |
| Why CUDA errors? | Memory starvation, multiple models fighting for GPU |
| Can RTX run same workload? | No - needs smaller context or model |
| Backend choice? | TensorRT-LLM (not vLLM) |
| Orchestration? | Still undecided, Docker Compose likely |
| Air-gapped? | Yes, no internet, all local |

---

## Next Actions

1. **Today:** Finalize infrastructure questions for Nishant
2. **Tomorrow:** Internal review meeting (Dec 9)
3. **Dec 10-11:** Client call with prepared questions
4. **Week 1:** Get hardware access, deploy baseline
