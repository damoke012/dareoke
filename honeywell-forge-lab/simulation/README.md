# Dual-SKU Simulation Environment

Simulate both Honeywell Forge Cognition hardware SKUs on a single x86_64 machine.

## The Problem

You have:
- One x86_64 machine with Tesla P40
- Need to test deployment for TWO different architectures

## The Solution

We can't truly emulate ARM64 on x86 efficiently, but we can:

1. **Simulate SKU behavior** via environment variables
2. **Use Docker profiles** to apply different configs
3. **Build multi-arch** and verify manifests
4. **Mock architecture detection** for testing

---

## Quick Start

```bash
# Simulate Jetson Thor deployment
./simulation/run-as-jetson.sh

# Simulate RTX 4000 Pro deployment
./simulation/run-as-rtx.sh

# Compare both side-by-side
./simulation/compare-skus.sh
```

---

## How It Works

### SKU Override

The container accepts `FORGE_SKU` environment variable to force a specific profile:

```bash
# Force Jetson Thor config (even on x86)
docker run -e FORGE_SKU=jetson_thor ...

# Force RTX 4000 Pro config
docker run -e FORGE_SKU=rtx_4000_pro ...
```

### What Gets Simulated

| Aspect | Simulated | Not Simulated |
|--------|-----------|---------------|
| Config values (sessions, thresholds) | ✅ | |
| Memory limits | ✅ | |
| Quantization settings | ✅ | |
| API responses | ✅ | |
| Actual ARM64 execution | | ❌ |
| Jetson-specific CUDA paths | | ❌ |
| Unified memory behavior | | ❌ |

### Multi-Arch Build Verification

You CAN build for both architectures using buildx:

```bash
# This builds ARM64 binary using QEMU emulation (slow but works)
docker buildx build --platform linux/arm64 -t forge:jetson-test .

# Inspect the manifest
docker buildx imagetools inspect forge-inference:latest
```
