# Performance Tuning Guide

## The Problem We're Solving

From the benchmark slides:
- **Current TTFT P99: 85 seconds** (unacceptable)
- **GPU Reserved: 50GB**
- **Input Tokens: 20k**
- **Concurrency: 20 users**

## Infrastructure Levers for Performance

### 1. KV Cache Optimization (Biggest Win)

**What is KV Cache?**
- Stores key-value pairs from attention layers
- Grows with context length (20k tokens = huge cache)
- Default FP32 uses 4 bytes per value

**The Fix: FP8 KV Cache**
```yaml
# sku_profiles.yaml
tensorrt_llm:
  kv_cache_dtype: "fp8"  # vs "fp32"
```

| Dtype | Memory per 20k context | Savings |
|-------|------------------------|---------|
| FP32  | ~45GB                  | baseline |
| FP16  | ~22GB                  | 2x |
| FP8   | ~11GB                  | 4x |

**Impact:** Frees 34GB for more concurrent sessions

### 2. Paged Attention

**What it does:**
- Allocates KV cache in blocks instead of contiguously
- Reduces memory fragmentation
- Enables dynamic memory allocation

```yaml
tensorrt_llm:
  use_paged_kv_cache: true
  tokens_per_block: 64    # Jetson Thor
  tokens_per_block: 32    # RTX 4000 (tighter memory)
```

**Impact:** Better memory utilization, fewer OOM errors

### 3. Chunked Context

**What it does:**
- Processes long contexts in chunks
- Better for 20k+ token inputs
- Reduces peak memory usage

```yaml
tensorrt_llm:
  enable_chunked_context: true
  max_num_tokens: 8192    # Jetson Thor
  max_num_tokens: 4096    # RTX 4000
```

**Impact:** Handles long contexts without OOM

### 4. Scheduler Policy

**Options:**
- `max_utilization`: Maximize GPU usage, may evict sessions
- `guaranteed_no_evict`: Never evict, may reject requests

```yaml
# Jetson Thor (128GB) - can afford aggressive scheduling
tensorrt_llm:
  scheduler_policy: "max_utilization"

# RTX 4000 (20GB) - must be conservative
tensorrt_llm:
  scheduler_policy: "guaranteed_no_evict"
```

**Impact:** Tradeoff between throughput and predictability

### 5. Session Limits

**Why it matters:**
- Each session holds KV cache in memory
- Too many sessions = OOM
- Too few = underutilization

```yaml
# Per-SKU limits
jetson_thor:
  inference:
    max_concurrent_sessions: 20   # 128GB unified

rtx_4000_pro:
  inference:
    max_concurrent_sessions: 8    # 20GB VRAM
```

### 6. Queue Depth Management

**What it does:**
- Limits pending requests
- Prevents thundering herd
- Graceful degradation

```yaml
thresholds:
  max_queue_depth: 10   # Jetson Thor
  max_queue_depth: 5    # RTX 4000
```

**Behavior when exceeded:** Returns HTTP 503 with "Queue full"

## Performance Targets by SKU

### Jetson AGX Thor (128GB Unified)
| Metric | Target | Notes |
|--------|--------|-------|
| TTFT | 500ms | Down from 85s! |
| TTFT P99 | 2000ms | Worst case |
| TPS | 60 | Output tokens/sec |
| Concurrent Sessions | 20 | Max users |
| Queue Depth | 10 | Before rejection |

### RTX 4000 Pro (20GB VRAM)
| Metric | Target | Notes |
|--------|--------|-------|
| TTFT | 750ms | Slightly higher |
| TTFT P99 | 3000ms | Memory-constrained |
| TPS | 50 | Output tokens/sec |
| Concurrent Sessions | 8 | VRAM limited |
| Queue Depth | 5 | Conservative |

## Monitoring Endpoints

### Check Current Performance Config
```bash
curl http://localhost:8000/v1/performance/targets
```

### Check TensorRT-LLM Settings
```bash
curl http://localhost:8000/v1/tensorrt-llm/config
```

### Prometheus Metrics
```bash
curl http://localhost:8000/metrics
```

Key metrics:
- `forge_ttft_seconds` - TTFT histogram
- `forge_tokens_per_second` - TPS histogram
- `forge_active_sessions` - Current session count
- `forge_gpu_memory_used_bytes` - GPU memory usage
- `forge_queue_depth` - Request queue depth

## Grafana Alerts

Set up alerts for:

1. **TTFT exceeds target**
   ```
   histogram_quantile(0.99, forge_ttft_seconds) > forge_target_ttft_p99_ms / 1000
   ```

2. **GPU memory critical**
   ```
   forge_gpu_memory_used_bytes / forge_gpu_memory_total_bytes > 0.85
   ```

3. **Session limit approaching**
   ```
   forge_active_sessions / forge_max_sessions > 0.9
   ```

4. **Queue backing up**
   ```
   forge_queue_depth > forge_max_queue_depth * 0.8
   ```

## Tuning Workflow

1. **Start with defaults** - Use SKU profiles as baseline
2. **Monitor under load** - Run load tests with 20 concurrent users
3. **Identify bottleneck**:
   - High TTFT + low GPU util = memory pressure (reduce sessions)
   - High TTFT + high GPU util = compute bound (reduce batch size)
   - OOM errors = reduce KV cache fraction or sessions
4. **Adjust one parameter at a time**
5. **Re-test and compare**

## Quick Wins Checklist

- [ ] KV Cache dtype set to FP8 (if supported)
- [ ] Paged attention enabled
- [ ] Chunked context enabled for 20k+ inputs
- [ ] Session limits enforced per SKU
- [ ] Queue depth limits set
- [ ] Prometheus metrics exposed
- [ ] Grafana alerts configured
