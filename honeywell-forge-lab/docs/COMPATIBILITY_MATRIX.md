# Compatibility Matrix - Honeywell Forge Cognition

## Task: Verify compatibility across all target SKUs

---

## Hardware SKUs

| SKU | Architecture | GPU Memory | Compute Cap | Status |
|-----|--------------|------------|-------------|--------|
| **Jetson AGX Thor** | ARM64 (aarch64) | 128GB unified | 8.7 (Ampere) | Pending hardware access |
| **Blackwell RTX Pro 4000** | x86_64 | 20GB dedicated | 9.0 (Blackwell) | Pending hardware access |
| **Tesla P40 (Lab)** | x86_64 | 24GB dedicated | 6.1 (Pascal) | Available for testing |

---

## Software Compatibility Matrix

### TensorRT-LLM Compatibility

| Feature | Jetson Thor | RTX Pro 4000 | Tesla P40 (Lab) |
|---------|-------------|--------------|-----------------|
| TensorRT-LLM | ✅ Yes | ✅ Yes | ⚠️ Limited |
| FP8 Quantization | ✅ Native | ✅ Native | ❌ No (Pascal) |
| FP16 Quantization | ✅ Yes | ✅ Yes | ✅ Yes |
| INT8 Quantization | ✅ Yes | ✅ Yes | ✅ Yes |
| Paged Attention | ✅ Yes | ✅ Yes | ✅ Yes |
| In-flight Batching | ✅ Yes | ✅ Yes | ✅ Yes |
| KV Cache FP8 | ✅ Yes | ✅ Yes | ❌ No |
| Chunked Context | ✅ Yes | ✅ Yes | ✅ Yes |

### Container/Runtime Compatibility

| Component | Jetson Thor | RTX Pro 4000 | Tesla P40 (Lab) |
|-----------|-------------|--------------|-----------------|
| Docker | ✅ Yes | ✅ Yes | ✅ Yes |
| containerd | ✅ Yes | ✅ Yes | ✅ Yes |
| nvidia-container-toolkit | ✅ Yes | ✅ Yes | ✅ Yes |
| K3s | ⚠️ ARM64 build | ✅ Yes | ✅ Yes |
| NVIDIA Device Plugin | ✅ Yes | ✅ Yes | ✅ Yes |

### GPU Features

| Feature | Jetson Thor | RTX Pro 4000 | Tesla P40 (Lab) |
|---------|-------------|--------------|-----------------|
| MIG (Multi-Instance GPU) | ❌ No | ❌ No | ❌ No |
| MPS (Multi-Process Service) | ⚠️ TBD | ✅ Yes (Blackwell) | ❌ No (Pascal) |
| Time-Slicing | ✅ Yes | ✅ Yes | ✅ Yes |
| NVLink | ✅ Available | ❌ No | ❌ No |
| GPU Passthrough (VM) | N/A (bare metal) | ✅ Yes | ✅ Yes |

### Base Image Compatibility

| Image | Jetson Thor | RTX Pro 4000 | Tesla P40 (Lab) |
|-------|-------------|--------------|-----------------|
| nvcr.io/nvidia/l4t-tensorrt | ✅ Required | ❌ N/A | ❌ N/A |
| nvcr.io/nvidia/tensorrt | ❌ N/A | ✅ Yes | ✅ Yes |
| nvcr.io/nvidia/tritonserver | ⚠️ ARM64 build | ✅ Yes | ✅ Yes |
| Ubuntu 22.04 | ✅ L4T based | ✅ Yes | ✅ Yes |

---

## Version Compatibility

### CUDA Versions

| SKU | Recommended CUDA | Min CUDA | Max CUDA |
|-----|------------------|----------|----------|
| Jetson Thor | 12.2 (JetPack 6.x) | 12.0 | 12.3 |
| RTX Pro 4000 | 12.2 | 12.0 | 12.4 |
| Tesla P40 | 12.2 | 11.0 | 12.4 |

### TensorRT Versions

| SKU | Recommended | Notes |
|-----|-------------|-------|
| Jetson Thor | 8.6.x (JetPack) | Must match JetPack version |
| RTX Pro 4000 | 8.6.x or 9.x | Blackwell support in 9.x |
| Tesla P40 | 8.6.x | Pascal supported |

### Driver Versions

| SKU | Recommended | Min Version |
|-----|-------------|-------------|
| Jetson Thor | JetPack 6.0+ | N/A (integrated) |
| RTX Pro 4000 | 535.x or 545.x | 535.86 |
| Tesla P40 | 535.x | 525.x |

---

## Model Compatibility

### Honeywell 9B Model (Expected)

| Aspect | Requirement | Jetson Thor | RTX Pro 4000 | Tesla P40 |
|--------|-------------|-------------|--------------|-----------|
| Model Size | ~18GB (FP16) | ✅ Fits | ⚠️ Tight | ✅ Fits |
| Model Size | ~9GB (FP8) | ✅ Fits | ✅ Fits | ❌ No FP8 |
| Model Size | ~9GB (INT8) | ✅ Fits | ✅ Fits | ✅ Fits |
| Context Length | 20K tokens | ✅ Yes | ⚠️ Limited | ⚠️ Limited |
| KV Cache (20 sessions) | ~40GB FP8 | ✅ Fits | ❌ Too large | ❌ Too large |
| KV Cache (20 sessions) | ~10GB FP8 optimized | ✅ Fits | ⚠️ Tight | ⚠️ Tight |

### Recommended Configurations

| SKU | Quantization | Max Sessions | Max Batch | Context |
|-----|--------------|--------------|-----------|---------|
| Jetson Thor | FP8 | 20 | 16 | 20K |
| RTX Pro 4000 | FP8/INT8 | 8 | 8 | 8K |
| Tesla P40 | FP16/INT8 | 10 | 8 | 8K |

---

## Compatibility Verification Checklist

### Phase 1: Lab Testing (Tesla P40) ☐

- [ ] TensorRT-LLM installation
- [ ] FP16 model loading
- [ ] INT8 quantization
- [ ] Paged attention
- [ ] K3s + time-slicing
- [ ] Container deployment
- [ ] Health endpoints
- [ ] Prometheus metrics

### Phase 2: RTX Pro 4000 Testing ☐

- [ ] FP8 quantization
- [ ] Memory limits (20GB)
- [ ] MPS evaluation
- [ ] Thermal throttling
- [ ] 8 concurrent sessions

### Phase 3: Jetson Thor Testing ☐

- [ ] L4T base image
- [ ] ARM64 TensorRT-LLM
- [ ] Unified memory handling
- [ ] NVLink (if applicable)
- [ ] 20 concurrent sessions
- [ ] Thermal management

---

## Known Limitations

### Tesla P40 (Lab Only)
1. **No FP8** - Pascal architecture doesn't support FP8
2. **No MPS** - Multi-Process Service requires Volta+
3. **Higher latency** - Older architecture, expect 2x latency vs production
4. **Different behavior** - Lab results won't match production exactly

### RTX Pro 4000
1. **Limited VRAM** - 20GB constrains model size and sessions
2. **No NVLink** - Single GPU only
3. **Consumer-class** - May have different driver behavior than datacenter GPUs

### Jetson Thor
1. **ARM64** - Different container images required
2. **Unified memory** - Different memory management than discrete GPUs
3. **JetPack dependency** - Must match exact JetPack version
4. **Thermal constraints** - Edge device thermal limits

---

## Action Items for Compatibility

1. **Get Hardware Specs** (Honeywell)
   - [ ] Exact Jetson Thor model/JetPack version
   - [ ] Exact RTX Pro 4000 specs
   - [ ] CUDA/TensorRT versions installed

2. **Get Model Details** (Quantiphi)
   - [ ] Model architecture (transformer variant)
   - [ ] Current quantization format
   - [ ] TensorRT engine build settings
   - [ ] Expected input/output format

3. **Validate in Lab** (Our team)
   - [ ] Deploy TensorRT-LLM on Tesla P40
   - [ ] Test with similar-sized open model
   - [ ] Benchmark latency/throughput
   - [ ] Validate K3s + GPU time-slicing

4. **Cross-Platform Testing** (When hardware available)
   - [ ] Same tests on RTX Pro 4000
   - [ ] Same tests on Jetson Thor
   - [ ] Compare results across SKUs

---

## Questions for Honeywell (Compatibility-Specific)

1. What JetPack version is installed on Jetson Thor devices?
2. What CUDA/TensorRT versions are on each SKU?
3. Is the TensorRT engine pre-built, or do we build it?
4. What quantization is the model currently using?
5. Have you tested the model on both SKUs?
6. Any known compatibility issues we should be aware of?
