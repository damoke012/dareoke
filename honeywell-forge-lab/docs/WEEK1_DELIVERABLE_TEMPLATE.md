# Week 1 Deliverable: Discovery & Design

**Due:** End of Week 1 (Dec 15, 2024)

**Deliverable Components:**
1. Tech Stack Review & Feedback
2. Current-State Assessment Report and Dependency Mapping
3. Application Blueprints

---

## 1. Tech Stack Review & Feedback

### 1.1 Current Software Stack (From Honeywell)

| Component | Version | Notes |
|-----------|---------|-------|
| LLM Model | TBD | 9B parameters, 20k input tokens |
| Inference Backend | TBD | TensorRT-LLM expected, vLLM fallback |
| Vector Database | Milvus | For RAG retrieval |
| Orchestration | LangChain | Agent-based architecture |
| Embedding Model | TBD | For document embedding |
| Container Runtime | TBD | Docker/containerd expected |
| OS (Jetson Thor) | L4T / JetPack | Version TBD |
| OS (RTX Pro) | Ubuntu | Version TBD |

### 1.2 Quantiphi Recommendations

| Area | Current | Recommended | Rationale |
|------|---------|-------------|-----------|
| KV Cache | FP32 (assumed) | FP8 | 4x memory savings (45GB → 11GB) |
| Attention | Standard | Paged Attention | Reduces memory fragmentation |
| Batching | TBD | In-flight Batching | Better GPU utilization |
| Quantization | TBD | FP8 (Thor), FP16 (RTX) | Hardware-optimized |

### 1.3 Compatibility Assessment

- [ ] TensorRT-LLM compatibility with Honeywell model verified
- [ ] vLLM fallback tested (if TensorRT not compatible)
- [ ] JetPack version confirmed for Jetson Thor
- [ ] Driver/CUDA versions documented

---

## 2. Current-State Assessment Report

### 2.1 Performance Baseline (From Honeywell Benchmarks)

| Metric | Current Value | Target | Gap |
|--------|---------------|--------|-----|
| TTFT P99 | 85 seconds | <2 seconds | 42x improvement needed |
| GPU Memory | 50GB reserved | <40GB (Thor), <18GB (RTX) | 10-32GB reduction |
| Max Concurrent Sessions | Unknown | 20 (Thor), 8 (RTX) | TBD |
| Input Context | 20k tokens | 20k tokens | Maintain |

### 2.2 Root Cause Analysis

| Issue | Likely Cause | Proposed Fix |
|-------|--------------|--------------|
| 85s TTFT | FP32 KV cache consuming 45GB+ | FP8 KV cache reduces to 11GB |
| Memory saturation | No session limits | Implement per-SKU session limits |
| Latency spikes | Queue buildup | Max queue depth + rejection policy |

### 2.3 Hardware Readiness

#### Jetson AGX Thor
- [ ] Hardware received and powered on
- [ ] JetPack version verified: ______
- [ ] nvidia-smi / tegrastats working
- [ ] Docker + nvidia-container-toolkit configured
- [ ] Network access configured (VPN if needed)

#### Blackwell RTX Pro 4000
- [ ] Hardware received and powered on
- [ ] Driver version verified: ______
- [ ] CUDA version verified: ______
- [ ] Docker + nvidia-container-toolkit configured
- [ ] Network access configured

---

## 3. Dependency Mapping

### 3.1 Blocking Dependencies (From Honeywell)

| # | Dependency | Status | Owner | ETA |
|---|------------|--------|-------|-----|
| 1 | Hardware access (Thor + RTX) | ☐ Pending | Honeywell | |
| 2 | Forge Cognition software environment | ☐ Pending | Honeywell | |
| 3 | Container registry access | ☐ Pending | Honeywell | |
| 4 | API documentation for Maintenance Assist | ☐ Pending | Honeywell | |
| 5 | Sample datasets for benchmarking | ☐ Pending | Honeywell | |
| 6 | VPN/remote access credentials | ☐ Pending | Honeywell | |
| 7 | Thermal limits documentation | ☐ Pending | Honeywell | |

### 3.2 Non-Blocking (Quantiphi to Prepare)

| # | Item | Status | Owner |
|---|------|--------|-------|
| 1 | Deployment automation scripts | ✓ Done | Quantiphi |
| 2 | SKU profile configurations | ✓ Done | Quantiphi |
| 3 | CI/CD pipeline (air-gapped) | ✓ Done | Quantiphi |
| 4 | Performance monitoring setup | ✓ Done | Quantiphi |
| 5 | Benchmarking framework | ☐ In Progress | Quantiphi |

---

## 4. Application Blueprint

### 4.1 Deployment Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Forge Cognition Appliance               │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐│
│  │            Quantiphi Deployment Layer               ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  ││
│  │  │  Inference  │  │  Prometheus │  │   Health   │  ││
│  │  │   Server    │  │   Metrics   │  │   Checks   │  ││
│  │  └─────────────┘  └─────────────┘  └────────────┘  ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │              Honeywell Application Layer            ││
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ ││
│  │  │  Agent   │ │ LangChain│ │ Retriever│ │ Milvus │ ││
│  │  │ Service  │ │   API    │ │   API    │ │   DB   │ ││
│  │  └──────────┘ └──────────┘ └──────────┘ └────────┘ ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │                   NVIDIA Stack                      ││
│  │  ┌─────────────────────────────────────────────────┐││
│  │  │  TensorRT-LLM / vLLM  │  CUDA  │  Drivers      │││
│  │  └─────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 4.2 SKU-Specific Configuration

| Parameter | Jetson Thor | Blackwell RTX Pro 4000 |
|-----------|-------------|------------------------|
| GPU Memory | 128GB unified | 20GB dedicated |
| Max Sessions | 20 | 8 |
| KV Cache | FP8, 40GB | FP8, 8GB |
| Batch Size | 16 | 8 |
| NVLink | Yes | No |
| Target TTFT | 500ms | 750ms |

### 4.3 Optimization Plan (Weeks 2-7)

| Week | Focus Area | Key Activities |
|------|------------|----------------|
| W2-3 | Pipeline Benchmarking | Establish baseline, identify bottlenecks |
| W3-5 | Model Optimization | Quantization (FP4/FP8/FP16), TensorRT graph optimization |
| W4-6 | Memory Optimization | KV cache, paged attention, buffer reuse |
| W5-7 | Concurrency Optimization | Dynamic batching, session limits, thermal management |
| W7 | Deployment Scripts | Finalize air-gapped deployment automation |
| W8 | Documentation & Handover | Testing report, user notes, training |

---

## 5. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| TensorRT-LLM not compatible with model | Medium | High | vLLM fallback ready |
| Hardware delivery delayed | Medium | High | Use lab Tesla P40 for dev, RTX 4090 as proxy |
| Thermal throttling reduces concurrency | Medium | Medium | Thermal monitoring + dynamic scaling |
| 85s TTFT root cause differs | Low | High | Multiple optimization strategies ready |

---

## 6. Acceptance Criteria (Week 1)

- [ ] Tech stack documented with versions
- [ ] Current-state performance baseline captured
- [ ] Dependency list tracked with ownership
- [ ] Architecture blueprint approved by Honeywell
- [ ] Optimization plan reviewed

---

## Appendix: Questions for Discovery Deep Dive

1. What's the current TensorRT-LLM version being used (if any)?
2. Is the 85s TTFT under load or with single request?
3. What's the current KV cache configuration?
4. Are there existing Prometheus/Grafana dashboards?
5. What's the model loading time currently?
6. Is model sharding across multiple GPUs in scope?
7. What's the latency target per use case (chat vs batch)?
