# TensorRT-LLM Crash Course

Everything you need to know about TensorRT-LLM for the Honeywell project, explained for someone with infrastructure (not ML) background.

---

## What is TensorRT-LLM?

**Simple answer:** NVIDIA's framework to make LLMs run FAST on NVIDIA GPUs.

**Technical answer:** A library that compiles LLM models into optimized GPU code, with built-in features for serving multiple users efficiently.

```
Regular LLM (PyTorch)          TensorRT-LLM
       │                            │
       ▼                            ▼
   Slow inference              Fast inference
   ~10 tokens/sec              ~100+ tokens/sec
   High memory                 Optimized memory
   Single user                 Many concurrent users
```

---

## Why Not Just Use PyTorch?

| PyTorch (Hugging Face) | TensorRT-LLM |
|------------------------|--------------|
| Easy to use | Requires compilation step |
| Slow inference | 2-5x faster inference |
| High memory usage | Optimized memory |
| Good for training | Optimized for inference |
| Works anywhere | NVIDIA GPUs only |

**Honeywell needs TensorRT-LLM because:**
- Edge devices have limited resources
- Multiple users need fast responses
- Battery/power constraints (Jetson)

---

## Key Concepts You Need to Know

### 1. Model Compilation

Before running inference, the model must be "compiled" (converted):

```bash
# Simplified flow
Original Model (Hugging Face)
        │
        ▼
   [TensorRT-LLM Build]
        │
        ▼
   TensorRT Engine (.engine file)
        │
        ▼
   Fast Inference Ready
```

**Your role:** You may need to run compilation, or receive pre-compiled engines.

**Question to ask Monday:** "Are models already compiled to TensorRT-LLM format?"

---

### 2. Quantization

Reducing numerical precision to save memory and speed up inference.

```
FP32 (32-bit float)  → Most accurate, most memory
       │
       ▼
FP16 (16-bit float)  → Good balance (RTX 4000 Pro)
       │
       ▼
INT8 (8-bit integer) → Faster, less accurate
       │
       ▼
FP8 (8-bit float)    → Best of both (Jetson Thor)
```

**Honeywell context:**
- **Jetson Thor** → FP8 (has native hardware support)
- **RTX 4000 Pro** → FP16 (Ada architecture sweet spot)

---

### 3. KV Cache (Key-Value Cache)

**What it is:** Memory that stores previous conversation context.

**Why it matters:** Each concurrent user needs their own KV cache.

```
User 1: "What is HVAC?" → KV Cache 1 (~500MB)
User 2: "Explain pumps" → KV Cache 2 (~500MB)
User 3: "Motor issues"  → KV Cache 3 (~500MB)
...
```

**Memory impact:**
- More users = more KV cache = more VRAM needed
- This is why RTX (20GB) supports fewer sessions than Thor (128GB)

**In sku_profiles.yaml:**
```yaml
jetson_thor:
  kv_cache_gb: 40    # Can afford large cache

rtx_4000_pro:
  kv_cache_gb: 8     # Limited by VRAM
```

---

### 4. Batching Strategies

How multiple requests are processed together.

**Static Batching:**
```
Wait for N requests → Process all together → Return all
Problem: High latency for first user if waiting for batch to fill
```

**Dynamic/Continuous Batching:**
```
Process requests as they arrive
Add new requests to running batch
Return results as ready
Better latency, better throughput
```

**In-flight Batching (TensorRT-LLM feature):**
```
Requests join/leave batch mid-inference
No waiting for batch to complete
Best of both worlds
```

**In sku_profiles.yaml:**
```yaml
optimization:
  use_inflight_batching: true
```

---

### 5. Key Metrics

| Metric | What It Means | Target |
|--------|---------------|--------|
| **TTFT** | Time To First Token - how long until response starts | <100ms |
| **TPS** | Tokens Per Second - generation speed | >50 tps |
| **Latency** | Total time for complete response | <5s |
| **Throughput** | Requests handled per second | Depends on load |

**Why these matter for Honeywell:**
- Building technicians waiting for answers
- Real-time assistant feel
- Multiple users per appliance

---

## TensorRT-LLM Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    TensorRT-LLM Server                       │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Request   │  │   Batch     │  │   Model     │         │
│  │   Queue     │─▶│   Scheduler │─▶│   Executor  │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                          │                │                  │
│                          ▼                ▼                  │
│                   ┌─────────────┐  ┌─────────────┐          │
│                   │  KV Cache   │  │   TensorRT  │          │
│                   │  Manager    │  │   Engine    │          │
│                   └─────────────┘  └─────────────┘          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Common TensorRT-LLM Commands

### Check available models
```bash
# List supported model architectures
python -c "import tensorrt_llm; print(tensorrt_llm.models.__all__)"
```

### Build/compile a model
```bash
# Convert Hugging Face model to TensorRT-LLM
python build.py \
    --model_dir /path/to/hf_model \
    --output_dir /path/to/trt_engine \
    --dtype float16 \
    --max_batch_size 8 \
    --max_input_len 2048 \
    --max_output_len 512
```

### Run inference server
```bash
# Using Triton Inference Server
tritonserver --model-repository=/models
```

---

## Triton Inference Server

Often used WITH TensorRT-LLM for production serving.

```
┌─────────────────────────────────────────┐
│           Triton Server                  │
│                                          │
│  ┌────────────────────────────────┐     │
│  │     TensorRT-LLM Backend       │     │
│  │                                │     │
│  │  ┌──────────┐  ┌──────────┐   │     │
│  │  │ Model 1  │  │ Model 2  │   │     │
│  │  │ (Maint.) │  │ (Asset)  │   │     │
│  │  └──────────┘  └──────────┘   │     │
│  └────────────────────────────────┘     │
│                                          │
│  HTTP :8000 │ gRPC :8001 │ Metrics :8002│
└─────────────────────────────────────────┘
```

**Why Triton:**
- Multiple model support
- Load balancing
- Metrics built-in
- Health checks
- Dynamic batching

**Our Dockerfile uses Triton:**
```dockerfile
FROM nvcr.io/nvidia/tritonserver:24.08-trtllm-python-py3
```

---

## Memory Calculation (Rough)

For a 7B parameter model:

```
Base Model (FP16):    ~14 GB  (7B * 2 bytes)
Base Model (INT8):    ~7 GB   (7B * 1 byte)
KV Cache per user:    ~0.5-2 GB (depends on context length)
Runtime overhead:     ~2 GB

Total for 8 users (FP16):
  14 + (8 * 1) + 2 = ~24 GB  ← Fits RTX 4000 (20GB) barely
                              (need smaller model or fewer users)

Total for 20 users (FP16):
  14 + (20 * 1) + 2 = ~36 GB ← Fits Jetson Thor (128GB) easily
```

**This is why SKU session limits differ!**

---

## Optimization Techniques (What You'll Tune)

### 1. Paged Attention
- Manages KV cache like OS manages memory pages
- Reduces memory fragmentation
- Enabled in our config

### 2. Tensor Parallelism
- Split model across multiple GPUs
- Not needed for single-GPU Cognition appliances

### 3. Speculative Decoding
- Use small model to predict, large model to verify
- Can speed up generation

### 4. Context Length
- Longer context = more memory
- May need to limit for edge devices

---

## What You'll Actually Do (Infrastructure Side)

1. **Deploy TensorRT-LLM containers** ← Your prototype does this
2. **Configure resource limits** ← SKU profiles
3. **Monitor GPU memory** ← Prometheus/Grafana
4. **Tune batch sizes** ← Based on load testing
5. **Manage model engines** ← Storage, versioning

**What ML team does:**
- Model selection
- Fine-tuning
- Quantization decisions
- Accuracy testing

---

## Quick Reference Commands

```bash
# Check GPU memory
nvidia-smi

# Monitor GPU continuously
watch -n 1 nvidia-smi

# Check TensorRT-LLM version
python -c "import tensorrt_llm; print(tensorrt_llm.__version__)"

# Run Triton server
tritonserver --model-repository=/models --log-verbose=1

# Test inference endpoint
curl -X POST http://localhost:8000/v2/models/model/infer \
  -d '{"inputs":[{"name":"text_input","datatype":"BYTES","shape":[1],"data":["Hello"]}]}'
```

---

## Resources for Deeper Learning

1. **NVIDIA TensorRT-LLM GitHub**
   https://github.com/NVIDIA/TensorRT-LLM

2. **TensorRT-LLM Documentation**
   https://nvidia.github.io/TensorRT-LLM/

3. **Triton Inference Server**
   https://github.com/triton-inference-server

4. **Best Udemy Course (per your earlier research)**
   "Certified Infra AI Expert: End-to-End GPU-Accelerated AI"

---

## Cheat Sheet for Monday

| If They Say | They Mean |
|-------------|-----------|
| "Build the engine" | Compile model to TensorRT format |
| "What's the batch size?" | Max concurrent inferences |
| "KV cache OOM" | Out of memory from too many users |
| "TTFT regression" | First token is slower than before |
| "Quantize to INT8" | Reduce precision for speed/memory |
| "Paged attention enabled?" | Memory optimization technique |

---

*You don't need to be an ML expert. You need to know enough to deploy, monitor, and troubleshoot. This crash course covers that.*
