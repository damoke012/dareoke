# Forge Cognition Prototype

GPU-accelerated LLM inference platform prototype for the Honeywell Forge Cognition project.

## Overview

This prototype demonstrates:
- TensorRT-LLM optimized inference on OpenShift
- Triton Inference Server deployment
- Performance benchmarking framework
- Automated deployment scripts

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenShift Cluster                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              forge-inference namespace                   ││
│  │  ┌─────────────────┐     ┌──────────────────────────┐  ││
│  │  │  Triton Server  │────▶│  Model Repository (PVC)  │  ││
│  │  │  (GPU Pod)      │     │  - TensorRT-LLM Engine   │  ││
│  │  └────────┬────────┘     └──────────────────────────┘  ││
│  │           │                                              ││
│  │     ┌─────▼─────┐                                       ││
│  │     │  Service  │◀── HTTP :8000 (inference)             ││
│  │     │           │◀── gRPC :8001 (inference)             ││
│  │     │           │◀── HTTP :8002 (metrics)               ││
│  │     └───────────┘                                       ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   GPU Worker Node                        ││
│  │  ┌────────────┐  ┌─────────────────────────────────┐   ││
│  │  │ NVIDIA GPU │  │ GPU Operator                     │   ││
│  │  │ (P40/RTX)  │  │ - Driver, Toolkit, Device Plugin │   ││
│  │  └────────────┘  └─────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

1. OpenShift cluster with GPU node
2. NVIDIA GPU Operator installed
3. `oc` CLI configured

### Deploy

```bash
# Full deployment with model build (takes ~30 min)
cd deploy
./deploy.sh --build-model

# Or deploy infrastructure first, build model separately
./deploy.sh
oc apply -f manifests/04-model-build-job.yaml
```

### Health Check

```bash
./health_check.sh
```

### Run Benchmarks

```bash
cd benchmark
./run_benchmark.sh --concurrency 1,2,4,8 --requests 20
```

## Project Structure

```
forge-cognition-prototype/
├── README.md
├── deploy/
│   ├── deploy.sh              # Main deployment script
│   ├── health_check.sh        # Health check script
│   └── manifests/
│       ├── 01-namespace.yaml
│       ├── 02-pvc.yaml
│       ├── 03-triton-deployment.yaml
│       └── 04-model-build-job.yaml
├── benchmark/
│   ├── benchmark_llm.py       # Python benchmark suite
│   ├── run_benchmark.sh       # Benchmark runner
│   └── results/               # Benchmark outputs
├── models/
│   └── configs/               # Model configurations
└── docs/
    ├── architecture.md
    └── benchmarking.md
```

## Key Metrics (SOW KPIs)

| Metric | Description | Target |
|--------|-------------|--------|
| TTFT P50 | Time to first token (median) | < 100ms |
| TTFT P99 | Time to first token (99th percentile) | < 500ms |
| Throughput | Output tokens per second | > 50 tok/s |
| Concurrent Sessions | Simultaneous inference requests | 8+ |
| GPU Memory | Peak utilization | < 80% |

## Technologies

- **NVIDIA TensorRT-LLM**: Model optimization and inference
- **Triton Inference Server**: Production inference serving
- **OpenShift**: Container orchestration
- **NVIDIA GPU Operator**: GPU resource management

## Development

### Building Custom Models

```bash
# SSH into build pod
oc exec -it job/trtllm-model-build -n forge-inference -- bash

# Customize build parameters
trtllm-build \
    --checkpoint_dir /models/checkpoint \
    --output_dir /models/engine \
    --dtype float16 \
    --max_batch_size 16 \
    --max_input_len 4096
```

### Monitoring

```bash
# Watch GPU utilization
oc exec -n forge-inference deployment/triton-inference-server -- nvidia-smi -l 1

# View Triton logs
oc logs -f deployment/triton-inference-server -n forge-inference

# Access metrics
curl http://<triton-svc>:8002/metrics
```

## Relevance to Honeywell SOW

This prototype demonstrates competency in:

| SOW Requirement | Prototype Coverage |
|-----------------|-------------------|
| TensorRT-LLM optimization | ✅ Model build pipeline |
| Multi-GPU scaling | 🔶 Single GPU (Tesla P40) |
| Performance benchmarking | ✅ TTFT, throughput, concurrency |
| Deployment automation | ✅ Scripts and manifests |
| Memory optimization | ✅ KV-cache config |
| Concurrent sessions | ✅ Load testing |

## Next Steps

1. [ ] Install NVIDIA GPU Operator on cluster
2. [ ] Deploy Triton with TensorRT-LLM
3. [ ] Run baseline benchmarks
4. [ ] Experiment with quantization (INT8, FP8)
5. [ ] Test concurrent session scaling
6. [ ] Document optimization findings
