# Unified Deployment Architecture for Forge Cognition

## The Challenge

Honeywell requires a **single optimized solution** that deploys to both hardware SKUs:

| SKU | Hardware | Architecture | Key Differences |
|-----|----------|--------------|-----------------|
| **SKU 1** | Jetson AGX Thor | ARM64 (aarch64) | Unified memory, NVLink between chiplets, ~100W |
| **SKU 2** | RTX Pro 4000 | x86_64 | Discrete GPU, PCIe, ~200W |

## Unified Deployment Strategy

### 1. Container Architecture: Multi-Arch Images

Build containers that support both architectures:

```dockerfile
# Dockerfile.inference
# Use NVIDIA's multi-arch base images
ARG TARGETARCH
FROM nvcr.io/nvidia/tritonserver:24.01-trtllm-python-py3-${TARGETARCH}

# Common application code
COPY app/ /app/
COPY models/ /models/

# Architecture-specific optimizations handled at runtime
ENV DEVICE_TYPE=${TARGETARCH}
```

**Build Process:**
```bash
# Build for both architectures
docker buildx build --platform linux/amd64,linux/arm64 \
    -t forge-inference:latest \
    --push .
```

### 2. Configuration-Driven Optimization

Create a unified configuration that adapts to hardware:

```yaml
# config/deployment-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: forge-inference-config
data:
  # Auto-detected at runtime
  hardware_profiles.yaml: |
    profiles:
      jetson-thor:
        arch: aarch64
        gpu_memory: 64GB  # Unified memory
        nvlink: true
        power_mode: "MAXN"  # or 30W, 50W modes
        tensorrt_precision: fp16
        max_batch_size: 16
        kv_cache_fraction: 0.4

      rtx-pro-4000:
        arch: x86_64
        gpu_memory: 20GB  # Discrete VRAM
        nvlink: false
        tensorrt_precision: fp16
        max_batch_size: 8
        kv_cache_fraction: 0.3
```

### 3. Runtime Hardware Detection

```python
# app/hardware_detector.py
import os
import subprocess

def detect_hardware():
    """Detect which Forge Cognition SKU we're running on."""

    arch = os.uname().machine  # aarch64 or x86_64

    # Get GPU info
    result = subprocess.run(
        ['nvidia-smi', '--query-gpu=name,memory.total', '--format=csv,noheader'],
        capture_output=True, text=True
    )
    gpu_info = result.stdout.strip()

    if 'Thor' in gpu_info or arch == 'aarch64':
        return 'jetson-thor'
    elif 'RTX' in gpu_info or 'Pro 4000' in gpu_info:
        return 'rtx-pro-4000'
    else:
        # Fallback for dev environments (like Tesla P40)
        return 'development'

def load_profile(profile_name: str) -> dict:
    """Load optimization profile for detected hardware."""
    import yaml
    with open('/config/hardware_profiles.yaml') as f:
        profiles = yaml.safe_load(f)['profiles']
    return profiles.get(profile_name, profiles['rtx-pro-4000'])
```

### 4. Model Build Pipeline

Build TensorRT engines for both architectures:

```yaml
# build-pipeline.yaml
stages:
  - build-x86
  - build-arm64
  - package

build-x86:
  stage: build-x86
  image: nvcr.io/nvidia/tritonserver:24.01-trtllm-python-py3
  script:
    - trtllm-build --checkpoint_dir /models/ckpt \
        --output_dir /engines/x86_64 \
        --dtype float16 \
        --max_batch_size 8
  artifacts:
    paths:
      - /engines/x86_64/

build-arm64:
  stage: build-arm64
  image: nvcr.io/nvidia/tritonserver:24.01-trtllm-python-py3-arm64
  tags:
    - arm64  # Run on ARM64 builder
  script:
    - trtllm-build --checkpoint_dir /models/ckpt \
        --output_dir /engines/aarch64 \
        --dtype float16 \
        --max_batch_size 16  # Thor can handle larger batches
  artifacts:
    paths:
      - /engines/aarch64/
```

### 5. Kubernetes/Edge Deployment Manifest

```yaml
# deployment/forge-inference.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: forge-inference
spec:
  template:
    spec:
      containers:
      - name: inference
        image: forge-inference:latest
        env:
        - name: HARDWARE_PROFILE
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName  # Or use node labels
        resources:
          limits:
            nvidia.com/gpu: 1
        volumeMounts:
        - name: config
          mountPath: /config
        - name: engines
          mountPath: /engines
      volumes:
      - name: config
        configMap:
          name: forge-inference-config
      - name: engines
        persistentVolumeClaim:
          claimName: model-engines

      # Node affinity to schedule on correct hardware
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: nvidia.com/gpu.product
                operator: In
                values:
                - "NVIDIA-RTX-Pro-4000"
                - "NVIDIA-Jetson-AGX-Thor"
```

### 6. Unified API Layer

```python
# app/inference_server.py
from fastapi import FastAPI
from hardware_detector import detect_hardware, load_profile

app = FastAPI()

# Detect hardware at startup
HARDWARE = detect_hardware()
PROFILE = load_profile(HARDWARE)

@app.on_event("startup")
async def load_model():
    """Load the appropriate TensorRT engine for this hardware."""
    engine_path = f"/engines/{PROFILE['arch']}/model.plan"
    # Load TensorRT engine...

@app.post("/v1/inference")
async def inference(request: InferenceRequest):
    """Unified inference endpoint - works on both SKUs."""
    # Same API, optimized execution per hardware
    result = await run_inference(
        request.prompt,
        max_tokens=request.max_tokens,
        batch_size=PROFILE['max_batch_size']
    )
    return result

@app.get("/v1/hardware")
async def get_hardware_info():
    """Return detected hardware profile."""
    return {
        "hardware": HARDWARE,
        "profile": PROFILE,
        "capabilities": get_gpu_capabilities()
    }
```

## Updated 1-Week Sprint Plan

### Days 1-3: Single SKU Prototype (Current Plan)
- Deploy on Tesla P40 (proxy for RTX Pro 4000)
- Get TensorRT-LLM + Triton working
- Establish baseline benchmarks

### Days 4-5: Add Unified Architecture
- Create hardware detection module
- Build configuration-driven deployment
- Create multi-arch Dockerfile (even if only testing x86)
- Document architecture for Jetson Thor adaptation

### Days 6-7: Testing & Documentation
- Stress testing with concurrent sessions
- Create architecture diagrams for Honeywell
- Document how to extend to Jetson Thor

## Key Deliverables for Honeywell Meeting

1. **Architecture Diagram** showing unified deployment
2. **Working x86 Prototype** demonstrating the pattern
3. **Configuration Schema** for hardware profiles
4. **Benchmark Results** from Tesla P40 (RTX Pro proxy)
5. **Documentation** on extending to Jetson Thor

## Jetson Thor Specific Considerations

| Feature | Implementation |
|---------|---------------|
| Unified Memory | Larger KV-cache, less memory transfer overhead |
| NVLink | Enable multi-chiplet inference for larger models |
| Power Modes | Support 30W/50W/100W profiles via nvpmodel |
| ARM64 | Separate TensorRT engine builds |
| Thermal | Dynamic batch size based on temperature |

```bash
# Jetson-specific power management
nvpmodel -m 0  # MAXN mode for full performance
jetson_clocks   # Max clock speeds
```

## Repository Structure Update

```
forge-cognition-prototype/
├── deploy/
│   ├── manifests/
│   │   ├── base/                    # Common manifests
│   │   ├── overlays/
│   │   │   ├── rtx-pro-4000/       # RTX-specific
│   │   │   └── jetson-thor/        # Thor-specific
│   │   └── kustomization.yaml
│   └── configs/
│       └── hardware_profiles.yaml
├── build/
│   ├── Dockerfile.x86_64
│   ├── Dockerfile.aarch64
│   └── build-engines.sh
├── app/
│   ├── hardware_detector.py
│   ├── inference_server.py
│   └── config_loader.py
└── docs/
    └── UNIFIED_DEPLOYMENT_ARCHITECTURE.md
```

## Testing Without Jetson Thor

Your Tesla P40 is actually a good development proxy:

| Tesla P40 | RTX Pro 4000 | Development Value |
|-----------|--------------|-------------------|
| 24GB VRAM | ~20GB VRAM | Similar memory constraints |
| Pascal arch | Blackwell arch | Different, but tests TRT flow |
| x86_64 | x86_64 | Same architecture |

For Jetson Thor testing, you would need:
1. Actual Jetson Thor hardware (from Honeywell)
2. Or Jetson AGX Orin as development proxy
3. QEMU ARM64 emulation (slow but works for builds)
