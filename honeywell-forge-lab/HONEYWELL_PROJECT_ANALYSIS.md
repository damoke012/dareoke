# Honeywell Forge Cognition Project Analysis

## For: Dario (Platform Engineer / Infrastructure Lead)

**Project Duration:** 12 weeks (Dec 8, 2025 - Feb 28, 2026)
**Your Role:** Platform Engineer (US/Canada)

---

## Executive Summary

This is **NOT** a traditional Kubernetes/container orchestration project. It's primarily an **LLM inference optimization** engagement on constrained edge hardware. Container orchestration is **undefined** and may not even be used.

---

## Hardware Target Environment

### Two SKUs (Hardware Configurations):

| SKU | Hardware | Use Case |
|-----|----------|----------|
| **SKU 1** | NVIDIA Jetson AGX Thor | Embedded edge device |
| **SKU 2** | NVIDIA RTX 4000 Pro | Desktop/workstation GPU card |

**Both are packaged into a branded appliance called "Cognition"**

### Key Hardware Constraints:
- **Single device** deployments (not clusters)
- **Edge deployment** - no cloud, no data center
- Limited memory compared to cloud GPUs
- Thermal throttling limits
- NVLink only available on Jetson Thor (not RTX Pro)

---

## What This Project IS:

1. **LLM Inference Optimization** - Primary focus
   - TensorRT-LLM graph optimization
   - Quantization (FP4, FP8, FP16)
   - KV-cache optimization
   - Memory footprint tuning

2. **Performance Engineering**
   - Throughput & latency benchmarking
   - Concurrent session optimization
   - Dynamic batching
   - Pipeline parallelism

3. **Deployment Automation**
   - Automated deployment scripts
   - Modular deployment workflows
   - CI/CD ready scripts (but CI/CD is NOT primary focus)

4. **Testing & Validation**
   - Stress testing
   - Failover/rollback/recovery (container level only)
   - Benchmarking under load

---

## What This Project is NOT:

- ❌ **NOT Kubernetes orchestration** - orchestration method undefined
- ❌ **NOT multi-node cluster management**
- ❌ **NOT computer vision/camera analytics**
- ❌ **NOT application development**
- ❌ **NOT hardware procurement**
- ❌ **NOT cloud deployment**

---

## Your Responsibilities as Platform Engineer

From the SOW:

> **Platform Engineer Responsibilities:**
> - Define and validate compute/storage/network architecture for Forge Cognition
> - Validate hardware readiness and ensure compatibility of software stack with Blackwell/Thor designs
> - Develop deployment automation scripts (CI/CD ready) and modular deployment workflows
> - Implement environment setup validation, GPU resource planning, load distribution & node orchestration
> - Execute stress, failover, rollback and recovery tests for end-to-end system

### Week-by-Week Focus:

| Week | Deliverable | Your Role |
|------|-------------|-----------|
| 1 | Discovery & Design | Validate hardware, review tech stack, architecture blueprint |
| 2-3 | Model Optimization | Support ML team with GPU resource planning |
| 4 | Memory Optimization | Assist with GPU memory planning |
| 5 | Concurrent Run Optimization | Load distribution, deployment scripts |
| 6 | Testing & Validation | Stress tests, failover/rollback tests |
| 7-10 | Repeat for Phase 2 (Asset Engineering) | Same as above |
| 11-12 | Documentation & Handoff | Deployment runbooks, troubleshooting guide |

---

## Tech Stack (What You'll Work With)

### Confirmed:
- **TensorRT-LLM** - Primary inference framework
- **VLLM** - Fallback if TensorRT-LLM incompatible
- **Containers** - Containerized deployment (Docker)
- **NVIDIA Drivers/CUDA** - GPU runtime

### Likely (but undefined):
- Container runtime (Docker, containerd, cri-o)
- Possibly Kubernetes (K3s for edge?) - but NOT confirmed
- Triton Inference Server - possible but not mentioned

### NOT in scope:
- Full Kubernetes cluster management
- Cloud infrastructure (AWS, GCP, Azure)
- Multi-node orchestration

---

## Key Clarifications from Meeting Notes

### On Container Orchestration:
> "Containerization & Orchestration: Not yet defined if Kubernetes or other methods will be used—awaiting further discovery during project ramp-up."

### On CI/CD:
> "CICD: Not a primary focus at kickoff; may be addressed as platform stability matures."

### On Workload Type:
> "Primary workload is LLM-backed assistants ('Maintenance Assistant' and 'Asset Engineering Assistant'); no real-time computer vision/camera analytics expected for this scope."

### On Failover/Recovery:
> "Failover, rollback, and recovery tests will be limited to the model and container level, as firmware-level or full Jetson device failures will require physical intervention."

### On Cloud-Agnostic Architecture:
> From meeting notes: Honeywell wants a **cloud-agnostic solution** - the deployment must work independently of any specific cloud provider.

**What this means for you:**
- No AWS/Azure/GCP-specific services (avoid managed K8s like EKS/AKS/GKE)
- Deployment scripts must be portable
- If orchestration is used, it should be vanilla Kubernetes (K3s, MicroK8s) not cloud-managed
- Container images should work on any registry (not tied to ECR/ACR/GCR)
- Monitoring/observability should use open-source tools (Prometheus, not CloudWatch)

---

## What You Need to Prepare

### Technical Skills to Brush Up:

1. **TensorRT-LLM** (CRITICAL)
   - Not just TensorRT, specifically TensorRT-LLM
   - Model compilation and optimization
   - Inference server setup

2. **NVIDIA Jetson Platform**
   - JetPack SDK
   - Jetson containers
   - ARM64 architecture differences

3. **GPU Memory Management**
   - KV-cache concepts
   - Dynamic batching
   - Memory profiling

4. **Container Deployment on Edge**
   - Docker on ARM64 (Jetson)
   - Docker on x86 (RTX)
   - Resource constraints
   - GPU passthrough to containers

5. **Benchmarking & Load Testing**
   - Locust or similar
   - GPU metrics collection
   - Prometheus/DCGM exporter

### Skills You Can Deprioritize:

- Complex Kubernetes orchestration
- Multi-cluster management
- Cloud-native infrastructure
- Service mesh
- GitOps (Argo, Flux)

---

## Questions to Ask in Week 1 Discovery

### Infrastructure Questions:
1. What container runtime is pre-installed on Cognition devices?
2. Is there any orchestration layer planned (K3s, Docker Swarm, none)?
3. How will model updates be deployed to devices in production?
4. What monitoring/observability stack exists?
5. How are devices managed remotely?

### Deployment Questions:
1. What's the deployment artifact format (container images, model files)?
2. Where is the container registry (Honeywell internal, Harbor)?
3. What's the rollback strategy?
4. How do we handle A/B testing of models?

### Hardware Questions:
1. Can we get remote SSH access to Cognition devices?
2. What are the exact GPU memory limits?
3. What's the thermal throttling threshold?
4. Is there persistent storage on devices?

---

## Recommended Udemy Course

Based on this analysis, I recommend:

### **[Certified Infra AI Expert: End-to-End GPU-Accelerated AI](https://www.udemy.com/course/certified-nvidia-ai-expert/)**

**Why:**
- ✅ Covers Jetson devices specifically
- ✅ TensorRT for model optimization
- ✅ Edge AI deployment
- ✅ Container deployment for AI
- ✅ GPU resource planning
- ✅ Not focused on complex K8s (matches your project)

**Skip:**
- Heavy Kubernetes courses (not primary focus)
- Cloud infrastructure courses (not relevant)
- Computer vision courses (not in scope)

---

## Additional Learning Resources

### NVIDIA Official (Free):
1. [TensorRT-LLM Documentation](https://docs.nvidia.com/tensorrt-llm/index.html)
2. [Jetson AGX Thor Developer Guide](https://developer.nvidia.com/embedded/jetson-agx-thor)
3. [NVIDIA Deep Learning Institute - Free Courses](https://www.nvidia.com/en-us/training/)

### GTC 2025 Sessions:
- [Advanced Techniques for Inference Optimization With TensorRT-LLM](https://www.nvidia.com/en-us/on-demand/session/gtc25-S71693/)

---

## Summary: Your Focus Areas

| Priority | Area | Why |
|----------|------|-----|
| ⭐⭐⭐ | TensorRT-LLM deployment | Core project deliverable |
| ⭐⭐⭐ | GPU memory optimization | Critical for edge constraints |
| ⭐⭐⭐ | Jetson platform familiarity | One of two target SKUs |
| ⭐⭐ | Container deployment automation | Your primary deliverable |
| ⭐⭐ | Benchmarking/load testing | Week 5-6 deliverables |
| ⭐ | Kubernetes (K3s) | Only if discovered in Week 1 |
| ❌ | Complex K8s orchestration | Not in scope |

---

## Key Dates

- **Monday, Dec 8, 2025** - Kickoff call
- **Week 1** - Discovery & architecture
- **Daily syncs** - 9am Eastern
- **Feb 28, 2026** - Project end (non-negotiable)

---

*Document created: December 7, 2025*
