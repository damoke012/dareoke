# Monday Kickoff Preparation - Honeywell Forge Cognition

**Date:** December 8, 2025
**Your Role:** Platform Engineer / Infrastructure Lead
**Project:** 12-week Forge Cognition deployment optimization

---

## 1. KEY QUESTIONS TO ASK IN KICKOFF

### Hardware & Environment

| Question | Why It Matters |
|----------|----------------|
| "Do we have access to physical Jetson Thor and RTX 4000 Pro hardware, or will we use simulators initially?" | Determines if you can test real deployments Week 1 |
| "What's the current state of the Cognition appliance software? Is there an existing container/deployment?" | Know if you're building from scratch or modifying existing |
| "Are both SKUs at the same software maturity level, or is one ahead?" | Prioritization for testing |
| "What container registry will we use? Is there an existing Harbor/Artifactory?" | Affects your CI/CD pipeline design |

### Architecture & Orchestration

| Question | Why It Matters |
|----------|----------------|
| "Has a decision been made on container orchestration - K3s, plain Docker, or something else?" | Critical for deployment automation |
| "Is there an existing deployment mechanism on the Cognition appliances?" | Don't reinvent if something exists |
| "How are appliances currently updated in the field?" | Affects rollback/recovery strategy |
| "Will appliances have internet access or are they fully air-gapped?" | Affects image distribution strategy |

### LLM & Model Details

| Question | Why It Matters |
|----------|----------------|
| "Which LLM model(s) are we deploying? Size in parameters?" | Determines memory requirements, quantization needs |
| "Is the model already converted to TensorRT-LLM format, or is that part of our scope?" | Major work item if not done |
| "What's the expected concurrent user load per appliance?" | Drives session limit tuning |
| "Are there existing latency SLAs (TTFT, TPS targets)?" | Sets your optimization targets |

### Team & Process

| Question | Why It Matters |
|----------|----------------|
| "Who handles the ML/model side vs infrastructure side?" | Clarify your boundaries |
| "What's the communication channel - Slack, Teams, email?" | Stay connected |
| "Is there a shared repo/codebase, or do we create one?" | Know where to commit |
| "Who approves deployments to test hardware?" | Avoid blockers |

---

## 2. WHAT YOU'VE PREPARED (Your Talking Points)

If asked "What have you done to prepare?", you can say:

### Unified Deployment Architecture
> "I've built a prototype that addresses the dual-SKU requirement. Single container image that auto-detects whether it's running on Jetson Thor or RTX 4000 Pro and configures itself accordingly - session limits, memory thresholds, quantization settings."

### Key Features Implemented
- **Multi-arch Docker build** - One image tag, works on both ARM64 (Jetson) and x86_64 (RTX)
- **SKU auto-detection** - Reads architecture + GPU name, applies correct profile
- **SKU profiles** - YAML-based config for each hardware variant
- **Monitoring stack** - Prometheus + Grafana for GPU metrics
- **Load testing** - Locust-based concurrent session testing

### Code Location
```
honeywell-forge-lab/
├── inference-server/      # FastAPI server with SKU detection
├── deployment/            # Docker Compose for both SKUs
├── simulation/            # Dual-SKU testing on single machine
├── load-testing/          # Performance testing
└── docs/                  # Documentation
```

---

## 3. TECHNICAL TERMS YOU SHOULD KNOW

### TensorRT-LLM Specific

| Term | What It Means |
|------|---------------|
| **TTFT** | Time To First Token - latency before response starts |
| **TPS** | Tokens Per Second - generation speed |
| **KV Cache** | Key-Value cache - stores attention computations, uses lots of VRAM |
| **Quantization** | Reducing precision (FP32→FP16→INT8) to save memory/speed up |
| **FP8** | 8-bit floating point - Jetson Thor supports natively |
| **Paged Attention** | Memory optimization technique for KV cache |
| **In-flight Batching** | Processing multiple requests simultaneously |

### Jetson Specific

| Term | What It Means |
|------|---------------|
| **L4T** | Linux for Tegra - NVIDIA's Jetson OS |
| **JetPack** | NVIDIA's SDK for Jetson (includes CUDA, TensorRT) |
| **Unified Memory** | CPU and GPU share same RAM (128GB on Thor) |
| **MAXN** | Maximum performance power mode |

### General

| Term | What It Means |
|------|---------------|
| **Inference** | Running a trained model to get predictions |
| **Batch size** | Number of requests processed together |
| **Latency** | Time to complete one request |
| **Throughput** | Requests completed per second |

---

## 4. YOUR WEEK 1 EXPECTED TASKS

Based on SOW, you'll likely be doing:

| Task | Your Preparation |
|------|------------------|
| Environment setup | Docker, container registry access |
| Hardware validation | SSH access to test appliances |
| Baseline deployment | Your prototype is a starting point |
| Initial benchmarking | Load test scripts ready |

---

## 5. RISKS TO FLAG EARLY

Mention these if the opportunity arises:

1. **Model conversion** - If models aren't TensorRT-LLM ready, that's significant work
2. **Air-gapped deployment** - Need offline image distribution strategy
3. **Jetson availability** - If no Thor hardware, can only simulate ARM64
4. **Memory constraints on RTX** - 20GB vs 128GB means very different session limits

---

## 6. DEMO READY (If Asked)

You can show:

```bash
# Show the dual-SKU simulation
cd /workspaces/dareoke/honeywell-forge-lab
./simulation/compare-skus.sh

# This runs both "Jetson" and "RTX" configs side-by-side
# Shows different session limits, memory thresholds
```

**What it demonstrates:**
- Same container image
- Different behavior per SKU
- Auto-configuration working
- Monitoring integration

---

## 7. CONFIDENCE BUILDERS

Things you already know from your lab work:

| Experience | Relevance |
|------------|-----------|
| GPU passthrough troubleshooting | Same debugging skills for real hardware |
| NVIDIA driver lifecycle | GPU Operator concepts apply |
| Container GPU access | `--gpus all`, device plugins |
| Prometheus/Grafana | Same monitoring stack |
| OpenShift/K8s | If they use K3s, you know the concepts |

---

## 8. FIRST IMPRESSIONS TIPS

**Do:**
- Ask clarifying questions (shows engagement)
- Take notes
- Offer to share your prototype repo
- Be honest about what you don't know yet

**Don't:**
- Pretend to know TensorRT-LLM deeply (you're learning)
- Over-promise timelines
- Get stuck on Kubernetes if they're not using it

---

## 9. QUICK REFERENCE - THE TWO SKUs

```
┌─────────────────────────────────────────────────────────────┐
│                    JETSON AGX THOR                          │
├─────────────────────────────────────────────────────────────┤
│ CPU Architecture:  ARM64 (aarch64)                          │
│ Memory:            128GB unified (shared CPU/GPU)           │
│ Power:             100W TDP                                 │
│ Quantization:      FP8 native support                       │
│ Container Base:    L4T (Linux for Tegra)                    │
│ Target Sessions:   15-20 concurrent                         │
│ Use Case:          Remote/harsh environments                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    RTX 4000 PRO                             │
├─────────────────────────────────────────────────────────────┤
│ CPU Architecture:  x86_64                                   │
│ Memory:            20GB dedicated VRAM                      │
│ Power:             130W TDP                                 │
│ Quantization:      FP16 recommended                         │
│ Container Base:    Standard Ubuntu/RHEL                     │
│ Target Sessions:   5-8 concurrent                           │
│ Use Case:          Office/server room with power            │
└─────────────────────────────────────────────────────────────┘
```

---

*Good luck tomorrow! You're more prepared than you think.*
