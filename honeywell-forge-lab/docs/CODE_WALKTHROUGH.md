# Prototype Code Walkthrough

This explains every key piece of the Honeywell Forge Cognition prototype so you can confidently discuss it.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     UNIFIED CONTAINER                            │
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   server.py  │───▶│ sku_profiles │───▶│   Config     │      │
│  │  (FastAPI)   │    │    .yaml     │    │  (applied)   │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                                       │                │
│         ▼                                       ▼                │
│  ┌──────────────┐                      ┌──────────────┐        │
│  │  /v1/chat    │                      │  Session     │        │
│  │  /v1/sku     │                      │  Manager     │        │
│  │  /health     │                      │  (limits)    │        │
│  │  /metrics    │                      └──────────────┘        │
│  └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. The Dockerfile (Multi-Architecture)

**File:** `inference-server/Dockerfile`

```dockerfile
# KEY CONCEPT: Build-time architecture selection
ARG TARGETARCH=amd64

# Pull BOTH base images (only one gets used)
FROM nvcr.io/nvidia/tritonserver:24.08-trtllm-python-py3 AS base-amd64
FROM nvcr.io/nvidia/l4t-tensorrt:r36.3.0 AS base-arm64

# Magic line - selects correct base based on build platform
FROM base-${TARGETARCH} AS runtime
```

**How it works:**
- When you run `docker buildx build --platform linux/amd64` → uses tritonserver
- When you run `docker buildx build --platform linux/arm64` → uses l4t-tensorrt
- Same Dockerfile, different base images

**Why this matters:**
- Jetson Thor is ARM64 → needs L4T-based image
- RTX 4000 Pro is x86_64 → needs standard image
- One build command creates both variants

---

## 2. SKU Detection (Runtime)

**File:** `inference-server/server.py` - `detect_sku()` function

```python
def detect_sku() -> str:
    arch = platform.machine()  # Returns "x86_64" or "aarch64"

    if arch in ("aarch64", "arm64"):
        return "jetson_thor"      # ARM = definitely Jetson
    elif arch in ("x86_64", "AMD64"):
        # x86 could be RTX or dev machine - check GPU
        gpu_name = nvidia_smi_get_name()
        if "RTX 4000" in gpu_name:
            return "rtx_4000_pro"
        elif "Tesla P40" in gpu_name:
            return "tesla_p40"    # Your lab GPU
        else:
            return "generic"
    else:
        return "generic"
```

**How it works:**
1. Check CPU architecture first (ARM vs x86)
2. If x86, query GPU name via NVML
3. Return SKU identifier

**Why this matters:**
- Container auto-configures on startup
- No manual configuration needed per device
- Same image works everywhere

---

## 3. SKU Profiles (Configuration)

**File:** `inference-server/sku_profiles.yaml`

```yaml
jetson_thor:
  description: "NVIDIA Jetson AGX Thor"

  hardware:
    gpu_memory_gb: 128        # Unified memory
    gpu_memory_type: "unified"

  inference:
    max_concurrent_sessions: 20    # More sessions (more RAM)
    kv_cache_gb: 40                # Larger KV cache
    quantization: "FP8"            # Thor has native FP8

  thresholds:
    memory_warning_percent: 70     # Lower threshold (shared memory)
    target_ttft_ms: 80             # Faster target


rtx_4000_pro:
  description: "NVIDIA RTX 4000 Pro"

  hardware:
    gpu_memory_gb: 20         # Dedicated VRAM
    gpu_memory_type: "dedicated"

  inference:
    max_concurrent_sessions: 8     # Fewer sessions (less RAM)
    kv_cache_gb: 8                 # Smaller KV cache
    quantization: "FP16"           # FP16 for Ada architecture

  thresholds:
    memory_warning_percent: 80     # Higher threshold OK
    target_ttft_ms: 100            # Slightly slower target
```

**How it works:**
- YAML file loaded at startup
- Matched to detected SKU
- Values override defaults

**Why this matters:**
- Easy to tune per-SKU settings
- Non-code changes (ops-friendly)
- Add new SKUs without code changes

---

## 4. Session Management

**File:** `inference-server/server.py` - `SessionManager` class

```python
class SessionManager:
    def __init__(self, max_sessions: int):
        self.max_sessions = max_sessions  # From SKU profile!
        self.sessions = {}

    async def create_session(self) -> str:
        if len(self.sessions) >= self.max_sessions:
            raise HTTPException(
                status_code=503,
                detail=f"Max sessions ({self.max_sessions}) reached"
            )
        # Create new session...
```

**How it works:**
- `max_sessions` comes from SKU profile (20 for Thor, 8 for RTX)
- Returns 503 when limit reached
- Sessions tracked by ID

**Why this matters:**
- Prevents OOM on constrained hardware
- RTX automatically limits to 8
- Thor allows up to 20

---

## 5. API Endpoints

**File:** `inference-server/server.py`

| Endpoint | Purpose | Example Response |
|----------|---------|------------------|
| `GET /health` | Health check + SKU info | `{"status": "healthy", "sku": "jetson_thor"}` |
| `GET /v1/sku` | Full SKU details | `{"sku_name": "...", "applied_config": {...}}` |
| `POST /v1/chat` | Inference request | `{"response": "...", "metrics": {...}}` |
| `POST /v1/sessions` | Create session | `{"session_id": "abc123"}` |
| `GET /metrics` | Prometheus metrics | Prometheus format |

**Key endpoint - `/v1/sku`:**
```json
{
  "sku_name": "jetson_thor",
  "sku_description": "NVIDIA Jetson AGX Thor",
  "architecture": "aarch64",
  "applied_config": {
    "max_concurrent_sessions": 20,
    "gpu_memory_threshold": 0.85,
    "target_ttft_ms": 80,
    "quantization": "FP8"
  }
}
```

---

## 6. Docker Compose Structure

**Base file:** `deployment/docker-compose.yaml`
```yaml
services:
  forge-inference:
    environment:
      - FORGE_SKU_AUTO_DETECT=true  # Enable auto-detection
      - FORGE_SKU=${FORGE_SKU:-}    # Allow override
```

**Jetson override:** `deployment/docker-compose.jetson.yaml`
```yaml
services:
  forge-inference:
    environment:
      - FORGE_SKU=jetson_thor       # Force Jetson config
    deploy:
      resources:
        limits:
          memory: 100G              # Jetson has more RAM
```

**RTX override:** `deployment/docker-compose.rtx.yaml`
```yaml
services:
  forge-inference:
    environment:
      - FORGE_SKU=rtx_4000_pro      # Force RTX config
    deploy:
      resources:
        limits:
          memory: 16G               # RTX has less RAM
```

**Usage:**
```bash
# Auto-detect
docker-compose up -d

# Force Jetson
docker-compose -f docker-compose.yaml -f docker-compose.jetson.yaml up -d

# Force RTX
docker-compose -f docker-compose.yaml -f docker-compose.rtx.yaml up -d
```

---

## 7. Build Script

**File:** `scripts/build.sh`

```bash
# Single platform (auto-detect)
./scripts/build.sh

# Specific platform
./scripts/build.sh --jetson    # ARM64
./scripts/build.sh --rtx       # x86_64

# Both platforms (multi-arch)
./scripts/build.sh --multiarch --push
```

**Multi-arch creates a manifest list:**
```
forge-inference:latest
├── linux/amd64 → tritonserver base
└── linux/arm64 → l4t-tensorrt base
```

When you `docker pull`:
- On Jetson → gets ARM64 variant
- On RTX workstation → gets x86_64 variant

---

## 8. Simulation Environment

**File:** `simulation/compare-skus.sh`

Runs BOTH configurations on your single machine:

```bash
# Starts two containers:
# Port 8001 → Jetson Thor config (20 sessions)
# Port 8002 → RTX 4000 config (8 sessions)

./simulation/compare-skus.sh
```

**Demonstrates:**
- Same image, different behavior
- Session limits enforced differently
- Config comparison table

---

## 9. Key Files Summary

```
honeywell-forge-lab/
├── inference-server/
│   ├── Dockerfile          # Multi-arch build
│   ├── server.py           # FastAPI + SKU detection
│   ├── config.yaml         # Base config
│   └── sku_profiles.yaml   # Per-SKU settings
│
├── deployment/
│   ├── docker-compose.yaml        # Base deployment
│   ├── docker-compose.jetson.yaml # Jetson overrides
│   ├── docker-compose.rtx.yaml    # RTX overrides
│   └── prometheus.yml             # Monitoring config
│
├── simulation/
│   ├── compare-skus.sh     # Run both side-by-side
│   └── load-test-comparison.py
│
├── scripts/
│   ├── build.sh            # Multi-arch build helper
│   └── deploy.sh           # Deployment automation
│
└── docs/
    ├── MONDAY_KICKOFF_PREP.md
    ├── CODE_WALKTHROUGH.md     # This file
    └── LAB_EXERCISE_GPU_INFERENCE.md
```

---

## 10. How to Explain It Simply

> "The prototype is a single container image that works on both Jetson Thor and RTX 4000 Pro. When it starts, it detects the hardware - ARM vs x86, which GPU - and automatically applies the right configuration. Jetson gets 20 concurrent sessions, RTX gets 8. Same code, different behavior based on hardware. This is the 'unified solution' the SOW requires."

---

*Now you can walk through any file and explain what it does!*
