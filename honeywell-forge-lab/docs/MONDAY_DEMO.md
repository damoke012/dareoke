# Forge Cognition Lab - Monday Kickoff Demo

## Demo Purpose

Demonstrate to Honeywell team that we have:
1. Understanding of the edge inference challenge
2. Working prototype for performance testing
3. Framework to measure key KPIs (TTFT, TPS, concurrency)
4. Readiness to begin discovery

---

## Demo Script (5-10 minutes)

### 1. Show Architecture Understanding (2 min)

"Based on our initial understanding, here's what we've prototyped:"

```
┌─────────────────────────────────────────────────────────────┐
│                    FORGE COGNITION EDGE                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌───────────────────────────────────┐  │
│  │  User Query  │───▶│     Inference Server (FastAPI)    │  │
│  │              │    │                                    │  │
│  │ "What is the │    │  ┌─────────────────────────────┐  │  │
│  │  maintenance │    │  │    Session Manager          │  │  │
│  │  schedule?"  │    │  │  (Concurrent user tracking) │  │  │
│  │              │    │  └─────────────────────────────┘  │  │
│  └──────────────┘    │                                    │  │
│                      │  ┌─────────────────────────────┐  │  │
│                      │  │     TensorRT-LLM Engine     │  │  │
│                      │  │  (Optimized LLM inference)  │  │  │
│                      │  └─────────────────────────────┘  │  │
│                      │                                    │  │
│                      └───────────────────────────────────┘  │
│                                    │                         │
│                      ┌─────────────▼─────────────┐          │
│                      │    NVIDIA GPU (RTX/Thor)  │          │
│                      │    - Memory: 16-128GB     │          │
│                      │    - KV Cache per session │          │
│                      └───────────────────────────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2. Live Demo - Start Server (1 min)

```bash
# Terminal 1: Start inference server
cd honeywell-forge-lab/inference-server
python server.py
```

Show health check:
```bash
curl http://localhost:8000/health | jq
```

### 3. Show Session Management (1 min)

```bash
# Create sessions
curl -X POST http://localhost:8000/v1/sessions | jq

# List active sessions
curl http://localhost:8000/v1/sessions | jq
```

### 4. Run Quick Benchmark (2 min)

```bash
cd benchmarks
python benchmark_inference.py --host http://localhost:8000 --quick
```

**Key Talking Points:**
- "We measure TTFT (Time to First Token) - critical for user experience"
- "We track latency degradation as concurrent users increase"
- "This helps us determine optimal session limits per hardware SKU"

### 5. Show GPU Monitoring (1 min)

```bash
cd monitoring
python gpu-metrics.py
```

**Key Talking Points:**
- "Real-time GPU memory tracking"
- "We estimate concurrent session capacity based on memory"
- "This maps directly to RTX 4000 Pro and Jetson Thor constraints"

### 6. Prometheus Metrics (1 min)

```bash
curl http://localhost:8000/metrics | head -50
```

**Key Talking Points:**
- "Ready for integration with existing monitoring (Prometheus/Grafana)"
- "SLO tracking built-in (TTFT thresholds, error rates)"

---

## Key Messages for Honeywell

1. **We understand the challenge**: Multi-user LLM inference on constrained edge hardware

2. **We have tooling ready**: Benchmarks, load tests, monitoring

3. **We're focused on the right metrics**:
   - TTFT (Time to First Token)
   - Tokens per second
   - Concurrent session capacity
   - Memory efficiency

4. **We're ready for discovery**: Our framework is flexible - we need to understand:
   - Your current model architecture
   - Target performance numbers
   - Baseline measurements

---

## Questions to Ask Honeywell

During/after demo, gather:

1. "What are your current TTFT numbers? Target?"
2. "How many concurrent users do you need to support per device?"
3. "What model(s) are you using? (size, framework)"
4. "Do you have existing benchmarks we can compare against?"
5. "When can we get access to a test device or model?"

---

## Backup: If No GPU Available

Run in simulation mode (default behavior):
```bash
python server.py  # Uses simulated inference latencies
```

Still demonstrates:
- Session management
- Metrics collection
- API structure
- Benchmark framework

---

## Files to Have Ready

```
honeywell-forge-lab/
├── inference-server/server.py    # Main demo
├── benchmarks/benchmark_inference.py
├── monitoring/gpu-metrics.py
└── docs/SETUP.md
```

## Pre-Demo Checklist

- [ ] Server starts without errors
- [ ] Health endpoint returns healthy
- [ ] Benchmark script runs successfully
- [ ] GPU monitoring shows metrics (or simulation mode)
- [ ] Screen sharing setup for demo
