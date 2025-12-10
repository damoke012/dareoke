# Device Compatibility Matrix - Honeywell Forge Cognition

## Overview

This document provides detailed compatibility information for the two target edge AI platforms:
1. **Jetson AGX Thor** - ARM64 embedded platform with unified memory
2. **RTX Pro 4000 (Blackwell)** - x86_64 discrete GPU workstation

**Primary Inference Backend:** TensorRT-LLM (confirmed by Quantiphi, Dec 9 2024)

---

# Device 1: NVIDIA Jetson AGX Thor

## 1.1 Hardware Specifications

| Component | Specification | Notes |
|-----------|---------------|-------|
| **Platform** | NVIDIA Jetson AGX Thor | Next-gen embedded AI |
| **Architecture** | ARM64 (aarch64) | Requires ARM64 binaries |
| **CPU** | NVIDIA Custom ARM Cores | 12+ cores expected |
| **GPU** | NVIDIA Thor GPU | Ampere-based architecture |
| **GPU Compute Capability** | SM 8.7+ | Ampere generation |
| **Memory** | 128GB Unified | Shared CPU/GPU memory |
| **Memory Type** | LPDDR5X | High bandwidth |
| **Memory Bandwidth** | ~275 GB/s | Unified memory bus |
| **TDP** | 15W - 100W | Configurable power modes |
| **NVLink** | ✅ Available | For multi-chip configurations |
| **Form Factor** | Embedded Module | Industrial/Edge deployment |

## 1.2 Software Stack - Jetson Thor

### Operating System

| Component | Required Version | Notes |
|-----------|------------------|-------|
| **JetPack SDK** | 6.0+ | Mandatory - includes full stack |
| **L4T (Linux for Tegra)** | 36.x | NVIDIA custom Linux |
| **Ubuntu Base** | 22.04 LTS | Underlying distribution |
| **Kernel** | 5.15 (Tegra) | NVIDIA custom kernel |
| **glibc** | 2.35+ | Standard C library |

### NVIDIA Driver Stack

| Component | Required Version | Included In | Notes |
|-----------|------------------|-------------|-------|
| **NVIDIA Driver** | Integrated | JetPack 6.0 | Part of L4T |
| **CUDA Toolkit** | 12.2 | JetPack 6.0 | ARM64 build |
| **cuDNN** | 8.9.x | JetPack 6.0 | Deep learning primitives |
| **TensorRT** | 8.6.x | JetPack 6.0 | Inference optimizer |
| **cuBLAS** | 12.2.x | JetPack 6.0 | Linear algebra |
| **cuSPARSE** | 12.2.x | JetPack 6.0 | Sparse matrix ops |
| **NCCL** | 2.18.x | JetPack 6.0 | Multi-GPU comms |

### Inference Stack

| Component | Required Version | Source | Notes |
|-----------|------------------|--------|-------|
| **TensorRT-LLM** | 0.7.x+ | Build from source | ARM64 build required |
| **Triton Inference Server** | 24.01+ | NGC (ARM64) | `nvcr.io/nvidia/tritonserver:24.01-py3` |
| **PyTorch** | 2.1+ | NGC (ARM64) | For model conversion |
| **Transformers** | 4.35+ | pip | HuggingFace library |
| **tokenizers** | 0.15+ | pip | Fast tokenization |

### Container Stack

| Component | Required Version | Notes |
|-----------|------------------|-------|
| **Docker CE** | 24.x | Or nvidia-docker |
| **containerd** | 1.7.x | K3s default runtime |
| **nvidia-container-toolkit** | 1.14.x+ | GPU container support |
| **nvidia-container-runtime** | 3.14.x | Runtime hook |

### Container Base Images (Jetson)

```bash
# TensorRT Base (Recommended)
nvcr.io/nvidia/l4t-tensorrt:r36.2.0-devel

# PyTorch Base
nvcr.io/nvidia/l4t-pytorch:r36.2.0-pth2.1

# Triton Server
nvcr.io/nvidia/tritonserver:24.01-py3-igpu

# CUDA Base
nvcr.io/nvidia/l4t-cuda:12.2.0-devel
```

## 1.3 TensorRT-LLM Compatibility - Jetson Thor

### Supported Features

| Feature | Support | Notes |
|---------|---------|-------|
| **FP32 Inference** | ✅ Full | Baseline precision |
| **TF32 Inference** | ✅ Full | Tensor Float 32 |
| **FP16 Inference** | ✅ Full | Half precision |
| **BF16 Inference** | ✅ Full | Brain Float 16 |
| **FP8 Inference** | ✅ Full | 4x memory savings |
| **INT8 Inference** | ✅ Full | Quantized inference |
| **INT4 (AWQ/GPTQ)** | ✅ Full | Ultra-low precision |

### TensorRT-LLM Features

| Feature | Support | Notes |
|---------|---------|-------|
| **Paged Attention** | ✅ Yes | Memory efficient attention |
| **In-flight Batching** | ✅ Yes | Dynamic batching |
| **KV Cache FP8** | ✅ Yes | 4x cache memory savings |
| **KV Cache FP16** | ✅ Yes | Standard cache |
| **Chunked Context** | ✅ Yes | Long context support |
| **Speculative Decoding** | ✅ Yes | Faster generation |
| **Streaming Output** | ✅ Yes | Token-by-token |
| **Tensor Parallelism** | ✅ NVLink | Multi-chip support |
| **Pipeline Parallelism** | ✅ Yes | Model sharding |
| **Grouped Query Attention** | ✅ Yes | GQA models supported |

### Memory Configuration - Jetson Thor

| Configuration | Value | Notes |
|---------------|-------|-------|
| **Total Unified Memory** | 128GB | Shared CPU/GPU |
| **Recommended for Model** | 80-90GB | Leave headroom |
| **KV Cache Allocation** | 30-40GB | For 20 sessions |
| **System Reserve** | 10-15GB | OS and services |
| **gpu_memory_utilization** | 0.85-0.90 | TensorRT-LLM setting |

### Recommended TensorRT-LLM Config - Jetson Thor

```yaml
jetson_thor:
  tensorrt_llm:
    kv_cache_dtype: "fp8"
    kv_cache_free_gpu_memory_fraction: 0.85
    enable_chunked_context: true
    max_num_tokens: 8192
    use_paged_kv_cache: true
    tokens_per_block: 64
    scheduler_policy: "max_utilization"
    enable_kv_cache_reuse: true
    gpu_memory_utilization: 0.90
    max_batch_size: 16
    max_concurrent_sessions: 20
```

---

# Device 2: RTX Pro 4000 (Blackwell DGPU)

## 2.1 Hardware Specifications

| Component | Specification | Notes |
|-----------|---------------|-------|
| **Platform** | Workstation/Edge PC | x86_64 system |
| **Architecture** | x86_64 | Standard binaries |
| **GPU** | NVIDIA RTX Pro 4000 | Blackwell architecture |
| **GPU Compute Capability** | SM 9.0 | Blackwell generation |
| **GPU Memory** | 20GB GDDR6X | Dedicated VRAM |
| **Memory Type** | GDDR6X | High-speed discrete |
| **Memory Bandwidth** | ~500 GB/s | PCIe x16 |
| **TDP** | 130W | Fixed power |
| **NVLink** | ❌ Not Available | Single GPU only |
| **Form Factor** | PCIe Card | Standard workstation |

## 2.2 Software Stack - RTX Pro 4000

### Operating System

| Component | Required Version | Notes |
|-----------|------------------|-------|
| **Ubuntu** | 22.04 LTS | Recommended |
| **RHEL** | 8.x / 9.x | Enterprise alternative |
| **Rocky Linux** | 9.x | RHEL compatible |
| **Kernel** | 5.15+ | For Blackwell support |
| **glibc** | 2.35+ | Standard C library |

### NVIDIA Driver Stack

| Component | Min Version | Recommended | Notes |
|-----------|-------------|-------------|-------|
| **NVIDIA Driver** | 545.23 | 550.x+ | Blackwell requires newest |
| **CUDA Toolkit** | 12.3 | 12.4+ | Blackwell support |
| **cuDNN** | 8.9.x | 9.0+ | Deep learning primitives |
| **TensorRT** | 9.0 | 9.2+ | Blackwell optimizations |
| **cuBLAS** | 12.3.x | 12.4.x | Linear algebra |
| **NCCL** | 2.19.x | 2.20.x | Multi-GPU comms |

### Inference Stack

| Component | Required Version | Source | Notes |
|-----------|------------------|--------|-------|
| **TensorRT-LLM** | 0.8.x+ | NGC/GitHub | Blackwell optimized |
| **Triton Inference Server** | 24.01+ | NGC | `nvcr.io/nvidia/tritonserver:24.01-py3` |
| **PyTorch** | 2.2+ | NGC/pip | For model conversion |
| **Transformers** | 4.36+ | pip | HuggingFace library |
| **tokenizers** | 0.15+ | pip | Fast tokenization |

### Container Stack

| Component | Required Version | Notes |
|-----------|------------------|-------|
| **Docker CE** | 24.x | Standard Docker |
| **containerd** | 1.7.x | K3s default runtime |
| **nvidia-container-toolkit** | 1.14.x+ | GPU container support |
| **nvidia-container-runtime** | 3.14.x | Runtime hook |

### Container Base Images (RTX Pro 4000)

```bash
# TensorRT-LLM Base (Recommended)
nvcr.io/nvidia/tensorrt:24.01-py3

# Triton Server
nvcr.io/nvidia/tritonserver:24.01-py3

# PyTorch Base
nvcr.io/nvidia/pytorch:24.01-py3

# CUDA Base
nvcr.io/nvidia/cuda:12.4.0-devel-ubuntu22.04
```

## 2.3 TensorRT-LLM Compatibility - RTX Pro 4000

### Supported Features

| Feature | Support | Notes |
|---------|---------|-------|
| **FP32 Inference** | ✅ Full | Baseline precision |
| **TF32 Inference** | ✅ Full | Tensor Float 32 |
| **FP16 Inference** | ✅ Full | Half precision |
| **BF16 Inference** | ✅ Full | Brain Float 16 |
| **FP8 Inference** | ✅ Full | Blackwell native |
| **INT8 Inference** | ✅ Full | Quantized inference |
| **INT4 (AWQ/GPTQ)** | ✅ Full | Ultra-low precision |

### TensorRT-LLM Features

| Feature | Support | Notes |
|---------|---------|-------|
| **Paged Attention** | ✅ Yes | Memory efficient attention |
| **In-flight Batching** | ✅ Yes | Dynamic batching |
| **KV Cache FP8** | ✅ Yes | 4x cache memory savings |
| **KV Cache FP16** | ✅ Yes | Standard cache |
| **Chunked Context** | ✅ Yes | Long context support |
| **Speculative Decoding** | ✅ Yes | Faster generation |
| **Streaming Output** | ✅ Yes | Token-by-token |
| **Tensor Parallelism** | ❌ No | No NVLink |
| **Pipeline Parallelism** | ❌ No | Single GPU |
| **Grouped Query Attention** | ✅ Yes | GQA models supported |
| **MPS (Multi-Process)** | ✅ Yes | GPU sharing |

### Memory Configuration - RTX Pro 4000

| Configuration | Value | Notes |
|---------------|-------|-------|
| **Total VRAM** | 20GB | Dedicated GPU memory |
| **Recommended for Model** | 14-16GB | Conservative allocation |
| **KV Cache Allocation** | 3-4GB | For 8 sessions |
| **CUDA Context** | 1-2GB | Driver overhead |
| **gpu_memory_utilization** | 0.80-0.85 | TensorRT-LLM setting |

### Recommended TensorRT-LLM Config - RTX Pro 4000

```yaml
rtx_pro_4000:
  tensorrt_llm:
    kv_cache_dtype: "fp8"
    kv_cache_free_gpu_memory_fraction: 0.80
    enable_chunked_context: true
    max_num_tokens: 4096
    use_paged_kv_cache: true
    tokens_per_block: 32
    scheduler_policy: "guaranteed_no_evict"
    enable_kv_cache_reuse: true
    gpu_memory_utilization: 0.85
    max_batch_size: 8
    max_concurrent_sessions: 8
```

---

# Side-by-Side Comparison

## Hardware Comparison

| Specification | Jetson AGX Thor | RTX Pro 4000 |
|---------------|-----------------|--------------|
| **Architecture** | ARM64 (aarch64) | x86_64 |
| **GPU Generation** | Ampere (SM 8.7) | Blackwell (SM 9.0) |
| **GPU Memory** | 128GB Unified | 20GB Dedicated |
| **Memory Type** | LPDDR5X Unified | GDDR6X Discrete |
| **Memory Bandwidth** | ~275 GB/s | ~500 GB/s |
| **TDP** | 15-100W | 130W |
| **NVLink** | ✅ Yes | ❌ No |
| **Form Factor** | Embedded | PCIe Card |
| **Deployment** | Edge/Industrial | Workstation/Edge PC |

## Software Stack Comparison

| Component | Jetson AGX Thor | RTX Pro 4000 |
|-----------|-----------------|--------------|
| **OS Base** | L4T 36.x (Ubuntu 22.04) | Ubuntu 22.04 |
| **Driver** | JetPack Integrated | 550.x+ |
| **CUDA** | 12.2 (JetPack) | 12.4+ |
| **TensorRT** | 8.6.x (JetPack) | 9.2+ |
| **TensorRT-LLM** | 0.7.x+ (ARM64) | 0.8.x+ (x86) |
| **Container Image** | l4t-tensorrt:r36.2.0 | tensorrt:24.01-py3 |

## Feature Comparison

| Feature | Jetson AGX Thor | RTX Pro 4000 |
|---------|-----------------|--------------|
| **FP8 Quantization** | ✅ Yes | ✅ Yes |
| **FP16 Quantization** | ✅ Yes | ✅ Yes |
| **INT8 Quantization** | ✅ Yes | ✅ Yes |
| **INT4 (AWQ/GPTQ)** | ✅ Yes | ✅ Yes |
| **Paged Attention** | ✅ Yes | ✅ Yes |
| **In-flight Batching** | ✅ Yes | ✅ Yes |
| **KV Cache FP8** | ✅ Yes | ✅ Yes |
| **Tensor Parallelism** | ✅ NVLink | ❌ No |
| **MPS (Multi-Process)** | ⚠️ TBD | ✅ Yes |
| **MIG** | ❌ No | ❌ No |
| **Time-Slicing** | ✅ Yes | ✅ Yes |

## Performance Targets

| Metric | Jetson AGX Thor | RTX Pro 4000 |
|--------|-----------------|--------------|
| **Max Concurrent Sessions** | 20 | 8 |
| **Max Batch Size** | 16 | 8 |
| **Max Context Length** | 20K tokens | 8K tokens |
| **Target TTFT** | < 500ms | < 750ms |
| **Target TPS** | 60+ | 50+ |
| **Target P99 Latency** | < 2000ms | < 3000ms |

---

# Kubernetes/K3s Compatibility

## K3s Support

| Component | Jetson AGX Thor | RTX Pro 4000 |
|-----------|-----------------|--------------|
| **K3s Version** | 1.28.x (ARM64) | 1.28.x (x86) |
| **NVIDIA Device Plugin** | 0.14.x | 0.14.x |
| **GPU Operator** | 23.9.x (ARM64) | 23.9.x |
| **Time-Slicing** | ✅ Supported | ✅ Supported |
| **Helm** | 3.13.x | 3.13.x |

## Container Runtime

| Component | Jetson AGX Thor | RTX Pro 4000 |
|-----------|-----------------|--------------|
| **containerd** | 1.7.x | 1.7.x |
| **nvidia-container-toolkit** | 1.14.x | 1.14.x |
| **RuntimeClass** | nvidia | nvidia |

---

# Verification Commands

## Check System Information

```bash
# Architecture
uname -m
# Expected: aarch64 (Thor) or x86_64 (RTX)

# OS Version
cat /etc/os-release

# Kernel Version
uname -r
```

## Check NVIDIA Stack

```bash
# Driver Version
nvidia-smi --query-gpu=driver_version --format=csv,noheader

# CUDA Version
nvcc --version

# TensorRT Version
dpkg -l | grep tensorrt
# or
python3 -c "import tensorrt; print(tensorrt.__version__)"

# GPU Info
nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv

# Full GPU Details
nvidia-smi -q
```

## Check Container Stack

```bash
# Docker Version
docker --version

# NVIDIA Container Toolkit
nvidia-ctk --version

# Test GPU in Container
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

## Check TensorRT-LLM

```bash
# TensorRT-LLM Version
python3 -c "import tensorrt_llm; print(tensorrt_llm.__version__)"

# Check Available Backends
python3 -c "from tensorrt_llm import Builder; print('TensorRT-LLM available')"
```

---

# Model Compatibility

## Supported Model Architectures

| Model Type | Jetson AGX Thor | RTX Pro 4000 | Notes |
|------------|-----------------|--------------|-------|
| LLaMA/LLaMA2 | ✅ Yes | ✅ Yes | Full support |
| Mistral | ✅ Yes | ✅ Yes | Full support |
| Falcon | ✅ Yes | ✅ Yes | Full support |
| GPT-2/GPT-J | ✅ Yes | ✅ Yes | Full support |
| BLOOM | ✅ Yes | ✅ Yes | Full support |
| MPT | ✅ Yes | ✅ Yes | Full support |
| Nemotron | ✅ Yes | ✅ Yes | NVIDIA SLM |
| Phi-2/Phi-3 | ✅ Yes | ✅ Yes | Microsoft SLM |
| Qwen | ✅ Yes | ✅ Yes | Alibaba models |
| ChatGLM | ✅ Yes | ✅ Yes | Chinese LLM |

## Model Size Recommendations

| Model Size | Jetson AGX Thor | RTX Pro 4000 | Quantization |
|------------|-----------------|--------------|--------------|
| 1-3B params | ✅ Excellent | ✅ Excellent | FP16/FP8 |
| 7-8B params | ✅ Excellent | ✅ Good | FP8/INT8 |
| 13B params | ✅ Good | ⚠️ Tight | FP8/INT8 |
| 30B+ params | ⚠️ Possible | ❌ Too large | INT4 only |
| 70B+ params | ⚠️ INT4 only | ❌ Not supported | INT4 required |

---

# Thermal & Power Management

## Jetson AGX Thor

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Power Modes** | 15W, 30W, 50W, 100W | Configurable |
| **Default Mode** | 50W | Balanced |
| **Max Sustained** | 100W | Full performance |
| **Throttle Temp** | 83°C | Reduces clocks |
| **Max Temp** | 95°C | Shutdown threshold |
| **Cooling** | Active (fan) | Required for 100W |

```bash
# Check power mode (Jetson)
nvpmodel -q

# Set power mode
sudo nvpmodel -m 0  # Max performance (100W)
sudo nvpmodel -m 2  # Balanced (50W)
```

## RTX Pro 4000

| Parameter | Value | Notes |
|-----------|-------|-------|
| **TDP** | 130W | Fixed |
| **Idle Power** | ~15W | Low power state |
| **Peak Power** | 130W | Under load |
| **Throttle Temp** | 83°C | Reduces clocks |
| **Max Temp** | 93°C | Shutdown threshold |
| **Cooling** | Active (fan) | GPU cooler |

```bash
# Check power/temp (RTX)
nvidia-smi --query-gpu=power.draw,temperature.gpu --format=csv

# Set power limit (requires root)
sudo nvidia-smi -pl 120  # Limit to 120W
```

---

# CRITICAL: TensorRT-LLM Jetson Compatibility Issues

## The Problem

**TensorRT-LLM has significant compatibility issues with Jetson platforms (SM 8.7 architecture).**

As of December 2024, TensorRT-LLM on Jetson is in **PREVIEW STATUS** with known limitations:

| Issue | Description | Impact |
|-------|-------------|--------|
| **Missing SM_87 Kernels** | Fused MHA kernels not compiled for Jetson | Falls back to slower unfused attention |
| **Preview Release Only** | v0.12.0-jetson branch is preview, not production | Stability not guaranteed |
| **Limited Testing** | NVIDIA still validating various settings | May encounter unexpected issues |
| **Accuracy Degradation** | Users report accuracy drops (97% → 89-93%) | Model quality may suffer |

### Specific Errors You May See

```
[TensorRT-LLM][WARNING] Fall back to unfused MHA because of unsupported head size 128 in sm_87
```

This warning indicates the optimized attention kernels are NOT available, resulting in:
- **Slower inference** (unfused attention is less efficient)
- **Higher memory usage**
- **Potential accuracy issues**

### Root Cause

From [NVIDIA GitHub Issue #1516](https://github.com/NVIDIA/TensorRT-LLM/issues/1516):
> "TensorRT-LLM does not have the sm 87 fused mha kernels now."

The SM 8.7 (Jetson Orin/Thor) architecture kernels are simply not included in the standard builds.

---

## Our Mitigation Strategy

### Option 1: Use MLC LLM (Recommended for Jetson)

[MLC LLM](https://www.jetson-ai-lab.com/benchmarks.html) is already optimized for Jetson and near peak theoretical performance:

| Framework | Jetson Support | Performance | Stability |
|-----------|---------------|-------------|-----------|
| **MLC LLM** | ✅ Excellent | Near peak | Production ready |
| **llama.cpp** | ✅ Good | Good | Production ready |
| **TensorRT-LLM** | ⚠️ Preview | Best (when working) | Preview only |
| **vLLM** | ⚠️ Limited | Good | Compilation issues |

**Recommendation:** Use MLC LLM as primary backend on Jetson, with TensorRT-LLM as optional for specific models that work well.

### Option 2: Use TensorRT-LLM Preview with Caution

If TensorRT-LLM is required (per Quantiphi), follow these guidelines:

```yaml
# Jetson TensorRT-LLM Requirements
jetson_tensorrt_llm:
  version: "0.12.0-jetson"  # Use Jetson-specific branch
  jetpack: "6.1"            # L4T r36.4 required
  container: "dustynv/tensorrt_llm:0.12-r36.4.0"

  # Workarounds
  workarounds:
    - Use smaller batch sizes (reduce memory pressure)
    - Use FP16 instead of FP8 if accuracy issues
    - Test model accuracy before production
    - Monitor for fallback warnings in logs
```

### Option 3: Hybrid Approach (Best)

Use different backends for different platforms:

| Platform | Primary Backend | Fallback Backend |
|----------|-----------------|------------------|
| **Jetson Thor** | MLC LLM | TensorRT-LLM (if working) |
| **RTX Pro 4000** | TensorRT-LLM | vLLM |

This ensures:
- Production stability on Jetson with MLC
- Maximum performance on x86 with TensorRT-LLM
- Consistent API across platforms (both support OpenAI-compatible endpoints)

---

## Implementation Plan

### Phase 1: Validate on Lab (Tesla P40)
- Test TensorRT-LLM on x86 first
- Establish baseline performance
- Verify model conversion works

### Phase 2: Test on RTX Pro 4000
- Deploy TensorRT-LLM (should work well)
- Benchmark performance
- Validate accuracy

### Phase 3: Test on Jetson Thor
- Start with MLC LLM (stable)
- Attempt TensorRT-LLM preview
- Compare accuracy and performance
- Make final decision on backend

### Phase 4: Unified Deployment
- Abstract backend behind common API
- Use Triton Inference Server for both
- Configure per-platform backend selection

---

## Jetson-Specific Alternatives

### MLC LLM Setup (Recommended)

```bash
# Pull MLC container for Jetson
docker pull dustynv/mlc:0.1.0-r36.2.0

# Run with model
docker run --runtime nvidia -it --rm \
  -v /path/to/models:/models \
  dustynv/mlc:0.1.0-r36.2.0 \
  python3 -m mlc_llm serve /models/llama-7b-q4f16_1
```

### llama.cpp Setup (Stable Alternative)

```bash
# Pull llama.cpp container for Jetson
docker pull dustynv/llama_cpp:0.2.57-r36.2.0

# Run server
docker run --runtime nvidia -it --rm \
  -v /path/to/models:/models \
  -p 8080:8080 \
  dustynv/llama_cpp:0.2.57-r36.2.0 \
  --server -m /models/model.gguf --port 8080
```

### Performance Comparison (Jetson AGX Orin 64GB)

| Model | MLC (tok/s) | llama.cpp (tok/s) | TensorRT-LLM (tok/s) |
|-------|-------------|-------------------|----------------------|
| Llama-2-7B (INT4) | ~45 | ~35 | ~50* |
| Llama-2-13B (INT4) | ~25 | ~20 | ~30* |
| Mistral-7B (INT4) | ~48 | ~38 | ~55* |

*TensorRT-LLM performance when working correctly; may be lower with unfused MHA fallback.

---

## Questions for Honeywell/Quantiphi

Before finalizing the Jetson deployment strategy:

1. **Is TensorRT-LLM mandatory?** Or can we use MLC/llama.cpp on Jetson?
2. **What accuracy tolerance is acceptable?** (TensorRT-LLM preview may have ~5-8% accuracy drop)
3. **Have you tested TensorRT-LLM on Jetson Thor specifically?**
4. **What JetPack version will be on the production devices?**
5. **Is there a timeline for TensorRT-LLM SM_87 kernel support?**

---

# Known Limitations

## Jetson AGX Thor

1. **ARM64 Architecture**
   - Requires ARM64-specific container images
   - Some x86 Python packages may not be available
   - TensorRT-LLM must be built from source

2. **TensorRT-LLM Compatibility (CRITICAL)**
   - SM_87 fused MHA kernels NOT available
   - Preview release only (v0.12.0-jetson)
   - May have accuracy degradation
   - Consider MLC LLM as alternative

3. **Unified Memory**
   - CPU and GPU share memory pool
   - Memory contention possible under high load
   - Different allocation strategy than discrete GPUs

4. **JetPack Dependency**
   - Must match exact JetPack version for all components
   - Upgrades require full JetPack update
   - Limited to NVIDIA-provided CUDA/TensorRT versions

5. **Thermal Constraints**
   - Edge deployment may have limited cooling
   - Sustained 100W requires adequate airflow
   - May need to use lower power modes

## RTX Pro 4000

1. **Limited VRAM**
   - 20GB constrains model and batch sizes
   - Large models require aggressive quantization
   - KV cache limited for many concurrent sessions

2. **No NVLink**
   - Single GPU only
   - No tensor parallelism
   - Model must fit in single GPU

3. **Workstation Class**
   - Not datacenter-grade reliability
   - Consumer driver branch
   - May have different CUDA behavior than Tesla/A100

4. **New Architecture**
   - Blackwell is newest generation
   - Some software may need updates
   - Early driver versions may have bugs

---

# Action Items Checklist

## Before Deployment

- [ ] Verify JetPack version on Jetson Thor
- [ ] Verify driver version on RTX Pro 4000 system
- [ ] Confirm CUDA version matches TensorRT-LLM requirements
- [ ] Test container runtime with GPU access
- [ ] Validate TensorRT-LLM installation
- [ ] Check thermal solution adequacy
- [ ] Verify network connectivity for air-gapped deployment

## During Deployment

- [ ] Build/obtain ARM64 TensorRT-LLM for Jetson
- [ ] Convert model to TensorRT engine format
- [ ] Configure appropriate quantization (FP8/INT8)
- [ ] Set memory utilization parameters
- [ ] Configure K3s with GPU time-slicing
- [ ] Deploy Triton Inference Server
- [ ] Validate health endpoints

## Post Deployment

- [ ] Run benchmark suite
- [ ] Verify latency targets met
- [ ] Check memory utilization under load
- [ ] Monitor thermal behavior
- [ ] Validate concurrent session handling
- [ ] Test failover/recovery
