# Compatibility Matrix - Honeywell Forge Cognition

## Task: Verify compatibility across all target SKUs

**Last Updated:** Dec 9, 2024

---

## 1. Hardware Specifications

### Jetson AGX Thor

| Component | Specification |
|-----------|---------------|
| **Architecture** | ARM64 (aarch64) |
| **GPU** | NVIDIA Thor (Next-gen) |
| **GPU Memory** | 128GB Unified (shared with CPU) |
| **Compute Capability** | 8.7+ (Ampere-based) |
| **TDP** | 100W configurable |
| **NVLink** | ✅ Available |
| **Form Factor** | Embedded module |

### Blackwell RTX Pro 4000

| Component | Specification |
|-----------|---------------|
| **Architecture** | x86_64 |
| **GPU** | NVIDIA Blackwell |
| **GPU Memory** | 20GB GDDR6X dedicated |
| **Compute Capability** | 9.0 (Blackwell) |
| **TDP** | 130W |
| **NVLink** | ❌ Not available |
| **Form Factor** | PCIe workstation GPU |

### Tesla P40 (Lab Environment)

| Component | Specification |
|-----------|---------------|
| **Architecture** | x86_64 |
| **GPU** | NVIDIA Pascal GP102 |
| **GPU Memory** | 24GB GDDR5X dedicated |
| **Compute Capability** | 6.1 (Pascal) |
| **TDP** | 250W |
| **NVLink** | ❌ Not available |
| **Form Factor** | PCIe datacenter GPU |

---

## 2. Complete Driver & Software Stack

### Jetson AGX Thor - Full Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **JetPack SDK** | 6.0+ | Required - includes everything |
| **L4T (Linux for Tegra)** | 36.x | Base OS |
| **NVIDIA Driver** | Integrated | Part of JetPack |
| **CUDA Toolkit** | 12.2 | Included in JetPack |
| **cuDNN** | 8.9.x | Included in JetPack |
| **TensorRT** | 8.6.x | Included in JetPack |
| **TensorRT-LLM** | 0.7.x+ | Must be ARM64 build |
| **NVIDIA Container Toolkit** | 1.14.x+ | For containerized workloads |
| **Docker** | 24.x | Or containerd 1.7.x |
| **Python** | 3.10+ | For inference server |
| **PyTorch** | 2.1+ (ARM64) | If needed |

**Container Base Image:**
```
nvcr.io/nvidia/l4t-tensorrt:r36.2.0-devel
```

### Blackwell RTX Pro 4000 - Full Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **OS** | Ubuntu 22.04 LTS | Recommended |
| **Kernel** | 5.15+ | For Blackwell support |
| **NVIDIA Driver** | 545.x+ | Blackwell requires newest |
| **CUDA Toolkit** | 12.3+ | Blackwell support |
| **cuDNN** | 8.9.x or 9.x | Deep learning primitives |
| **TensorRT** | 9.2+ | Blackwell optimizations |
| **TensorRT-LLM** | 0.8.x+ | Latest for Blackwell |
| **NVIDIA Container Toolkit** | 1.14.x+ | GPU container support |
| **Docker** | 24.x | Or containerd 1.7.x |
| **Python** | 3.10+ | For inference server |

**Container Base Image:**
```
nvcr.io/nvidia/tensorrt:24.01-py3
```

### Tesla P40 (Lab) - Full Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **OS** | Ubuntu 22.04 LTS | Recommended |
| **Kernel** | 5.15+ | Standard |
| **NVIDIA Driver** | 535.x | Stable for Pascal |
| **CUDA Toolkit** | 12.2 | Pascal compatible |
| **cuDNN** | 8.9.x | Pascal supported |
| **TensorRT** | 8.6.x | Pascal supported |
| **TensorRT-LLM** | 0.7.x | Pascal has limitations |
| **NVIDIA Container Toolkit** | 1.14.x+ | GPU container support |
| **Docker** | 24.x | Or containerd 1.7.x |
| **Python** | 3.10+ | For inference server |

**Container Base Image:**
```
nvcr.io/nvidia/tensorrt:23.10-py3
```

---

## 3. Version Compatibility Matrix

### Driver Compatibility

| GPU | Min Driver | Recommended Driver | Max Driver | Notes |
|-----|------------|-------------------|------------|-------|
| Jetson Thor | JetPack 6.0 | JetPack 6.0+ | JetPack 6.x | Integrated |
| RTX Pro 4000 | 545.23 | 545.29+ | Latest | Blackwell new |
| Tesla P40 | 525.60 | 535.129 | 545.x | Pascal mature |

### CUDA Compatibility

| GPU | Min CUDA | Recommended | Max CUDA | Compute Cap |
|-----|----------|-------------|----------|-------------|
| Jetson Thor | 12.0 | 12.2 | 12.3 | sm_87+ |
| RTX Pro 4000 | 12.3 | 12.4 | 12.4+ | sm_90 |
| Tesla P40 | 11.0 | 12.2 | 12.4 | sm_61 |

### TensorRT Compatibility

| GPU | Min TensorRT | Recommended | TensorRT-LLM | Notes |
|-----|--------------|-------------|--------------|-------|
| Jetson Thor | 8.6.0 | 8.6.2 | 0.7.x+ | ARM64 build required |
| RTX Pro 4000 | 9.0 | 9.2+ | 0.8.x+ | Blackwell optimized |
| Tesla P40 | 8.5.0 | 8.6.1 | 0.7.x | No FP8 support |

### cuDNN Compatibility

| GPU | Min cuDNN | Recommended | Notes |
|-----|-----------|-------------|-------|
| Jetson Thor | 8.9.0 | 8.9.4 | JetPack bundled |
| RTX Pro 4000 | 8.9.0 | 9.0+ | Blackwell optimized |
| Tesla P40 | 8.6.0 | 8.9.4 | Pascal compatible |

---

## 4. Feature Support Matrix

### Quantization Support

| Feature | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|---------|-------------|--------------|-----------|
| FP32 | ✅ Yes | ✅ Yes | ✅ Yes |
| TF32 | ✅ Yes | ✅ Yes | ❌ No |
| FP16 | ✅ Yes | ✅ Yes | ✅ Yes |
| BF16 | ✅ Yes | ✅ Yes | ❌ No |
| FP8 (E4M3) | ✅ Yes | ✅ Yes | ❌ No |
| FP8 (E5M2) | ✅ Yes | ✅ Yes | ❌ No |
| INT8 | ✅ Yes | ✅ Yes | ✅ Yes |
| INT4 (AWQ/GPTQ) | ✅ Yes | ✅ Yes | ⚠️ Limited |

### TensorRT-LLM Features

| Feature | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|---------|-------------|--------------|-----------|
| Paged Attention | ✅ Yes | ✅ Yes | ✅ Yes |
| In-flight Batching | ✅ Yes | ✅ Yes | ✅ Yes |
| KV Cache FP8 | ✅ Yes | ✅ Yes | ❌ No |
| KV Cache FP16 | ✅ Yes | ✅ Yes | ✅ Yes |
| Chunked Context | ✅ Yes | ✅ Yes | ✅ Yes |
| Speculative Decoding | ✅ Yes | ✅ Yes | ⚠️ Limited |
| Streaming | ✅ Yes | ✅ Yes | ✅ Yes |
| Multi-GPU (TP) | ✅ NVLink | ❌ No | ❌ No |

### GPU Isolation Features

| Feature | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|---------|-------------|--------------|-----------|
| MIG | ❌ No | ❌ No | ❌ No |
| MPS | ⚠️ TBD | ✅ Yes | ❌ No |
| Time-Slicing | ✅ Yes | ✅ Yes | ✅ Yes |
| vGPU | ❌ N/A | ⚠️ TBD | ✅ Yes |
| Memory Limits | ✅ Yes | ✅ Yes | ✅ Yes |

---

## 5. Container & Kubernetes Compatibility

### Container Runtime

| Component | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-----------|-------------|--------------|-----------|
| Docker CE | 24.x | 24.x | 24.x |
| containerd | 1.7.x | 1.7.x | 1.7.x |
| Podman | 4.x | 4.x | 4.x |
| nvidia-container-toolkit | 1.14.x | 1.14.x | 1.14.x |
| nvidia-container-runtime | 3.14.x | 3.14.x | 3.14.x |

### Kubernetes / K3s

| Component | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-----------|-------------|--------------|-----------|
| K3s | 1.28.x (ARM64) | 1.28.x | 1.28.x |
| K8s | 1.28.x (ARM64) | 1.28.x | 1.28.x |
| NVIDIA Device Plugin | 0.14.x | 0.14.x | 0.14.x |
| NVIDIA GPU Operator | 23.9.x | 23.9.x | 23.9.x |
| Helm | 3.13.x | 3.13.x | 3.13.x |

### Container Images

| Image | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-------|-------------|--------------|-----------|
| Base TensorRT | `l4t-tensorrt:r36.2.0` | `tensorrt:24.01-py3` | `tensorrt:23.10-py3` |
| Triton Server | `tritonserver:24.01-py3` (ARM) | `tritonserver:24.01-py3` | `tritonserver:23.10-py3` |
| PyTorch | `l4t-pytorch:r36.2.0` | `pytorch:24.01-py3` | `pytorch:23.10-py3` |

---

## 6. Operating System Compatibility

### Jetson Thor

| OS Component | Version | Notes |
|--------------|---------|-------|
| L4T Base | 36.x | NVIDIA Linux for Tegra |
| Ubuntu Base | 22.04 | Underlying distro |
| Kernel | 5.15 (Tegra) | NVIDIA custom kernel |
| glibc | 2.35 | Standard |
| Python | 3.10 | System default |

### RTX Pro 4000 / Tesla P40

| OS Component | Version | Notes |
|--------------|---------|-------|
| Ubuntu | 22.04 LTS | Recommended |
| RHEL | 8.x / 9.x | Enterprise option |
| Kernel | 5.15+ | For GPU support |
| glibc | 2.35+ | Standard |
| Python | 3.10+ | For inference |

---

## 7. Network & Storage Requirements

### Network

| Requirement | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-------------|-------------|--------------|-----------|
| Min Bandwidth | 1 Gbps | 1 Gbps | 1 Gbps |
| Recommended | 10 Gbps | 10 Gbps | 10 Gbps |
| Latency | < 10ms | < 10ms | < 10ms |

### Storage

| Requirement | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-------------|-------------|--------------|-----------|
| Model Storage | 50GB+ | 50GB+ | 50GB+ |
| Container Images | 30GB+ | 30GB+ | 30GB+ |
| Logs/Cache | 20GB+ | 20GB+ | 20GB+ |
| **Total Recommended** | 150GB SSD | 150GB SSD | 150GB SSD |
| Storage Type | NVMe preferred | NVMe preferred | SSD min |

---

## 8. Memory Requirements

### System Memory (RAM)

| Workload | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|----------|-------------|--------------|-----------|
| Minimum | N/A (unified) | 32GB | 32GB |
| Recommended | N/A (unified) | 64GB | 64GB |
| For 20 sessions | N/A (unified) | 64GB+ | 64GB+ |

### GPU Memory Allocation

| Component | Jetson Thor (128GB) | RTX Pro 4000 (20GB) | Tesla P40 (24GB) |
|-----------|---------------------|---------------------|------------------|
| Model (FP8) | ~9GB | ~9GB | N/A (use FP16) |
| Model (FP16) | ~18GB | ~18GB | ~18GB |
| KV Cache | 40GB (FP8) | 8GB (FP8) | 10GB (FP16) |
| CUDA Context | 2GB | 2GB | 2GB |
| Headroom | 10% | 15% | 15% |
| **Available for model** | ~115GB | ~17GB | ~20GB |

---

## 9. Thermal & Power

### Thermal Limits

| Parameter | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-----------|-------------|--------------|-----------|
| Max GPU Temp | 95°C | 93°C | 96°C |
| Throttle Temp | 83°C | 83°C | 85°C |
| Target Temp | < 75°C | < 75°C | < 80°C |
| Cooling | Active (fan) | Active (fan) | Passive (server) |

### Power

| Parameter | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|-----------|-------------|--------------|-----------|
| TDP | 100W | 130W | 250W |
| Idle | ~15W | ~15W | ~50W |
| Peak | 100W | 130W | 250W |
| PSU Requirement | Included | 650W+ | 1000W+ |

---

## 10. Compatibility Verification Commands

### Check Driver Version
```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
```

### Check CUDA Version
```bash
nvcc --version
# or
nvidia-smi | grep "CUDA Version"
```

### Check TensorRT Version
```bash
dpkg -l | grep tensorrt
# or in Python
python3 -c "import tensorrt; print(tensorrt.__version__)"
```

### Check Compute Capability
```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
```

### Check GPU Memory
```bash
nvidia-smi --query-gpu=memory.total --format=csv,noheader
```

### Full GPU Info
```bash
nvidia-smi -q
```

### Check Container Toolkit
```bash
nvidia-ctk --version
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```

---

## 11. Quick Reference Card

| Item | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|------|-------------|--------------|-----------|
| **Architecture** | ARM64 | x86_64 | x86_64 |
| **Compute Cap** | 8.7+ | 9.0 | 6.1 |
| **VRAM** | 128GB unified | 20GB | 24GB |
| **Driver** | JetPack 6.0+ | 545.x+ | 535.x |
| **CUDA** | 12.2 | 12.4 | 12.2 |
| **TensorRT** | 8.6.x | 9.2+ | 8.6.x |
| **FP8** | ✅ | ✅ | ❌ |
| **MPS** | ⚠️ | ✅ | ❌ |
| **Max Sessions** | 20 | 8 | 10 |
| **Base Image** | l4t-tensorrt | tensorrt:24.01 | tensorrt:23.10 |

---

## 12. Action Items

### Information Needed from Honeywell

- [ ] Exact JetPack version on Jetson Thor
- [ ] Exact driver version on RTX Pro 4000
- [ ] Current CUDA version on each device
- [ ] Current TensorRT version on each device
- [ ] Any custom kernel modules or drivers
- [ ] Network configuration (air-gapped?)
- [ ] Storage configuration (NVMe/SSD?)

### Information Needed from Quantiphi

- [ ] TensorRT engine build settings
- [ ] Model quantization format (FP8/FP16/INT8)
- [ ] Target CUDA/TensorRT versions for engine
- [ ] Any platform-specific optimizations
