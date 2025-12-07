# Honeywell Forge Cognition - Lab Prototype

## Purpose
Pre-build a functional prototype that demonstrates LLM inference optimization on constrained GPU hardware, simulating the Forge Cognition edge deployment scenario.

## Hardware Mapping

| Honeywell Target | Lab Proxy | Notes |
|------------------|-----------|-------|
| RTX 4000 Pro (~16-24GB) | Tesla P40 (24GB) | Good memory match |
| Jetson Thor (128GB unified) | Tesla P40 | Memory constrained simulation |

## Prototype Components

```
honeywell-forge-lab/
├── README.md                    # This file
├── inference-server/            # TensorRT-LLM inference service
│   ├── Dockerfile
│   ├── server.py
│   └── config.yaml
├── load-testing/                # Concurrent user simulation
│   ├── locustfile.py
│   └── scenarios/
├── monitoring/                  # GPU metrics & latency tracking
│   ├── gpu-metrics.py
│   └── dashboard.json
├── benchmarks/                  # Performance measurement scripts
│   ├── benchmark_inference.py
│   ├── memory_profiler.py
│   └── results/
├── deployment/                  # K8s/OpenShift manifests
│   ├── inference-deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── docs/
    ├── SETUP.md
    └── RESULTS.md
```

## Key Metrics to Demonstrate

1. **TTFT (Time to First Token)** - P50, P90, P99
2. **Tokens/second** - Input and output throughput
3. **Concurrent Sessions** - Max users before latency degradation
4. **GPU Memory** - Peak and sustained usage
5. **Latency Under Load** - Degradation curve

## Quick Start

```bash
# 1. Build inference server
cd inference-server
docker build -t forge-inference:latest .

# 2. Run with GPU
docker run --gpus all -p 8000:8000 forge-inference:latest

# 3. Run load test
cd ../load-testing
locust -f locustfile.py --host=http://localhost:8000

# 4. View metrics
cd ../monitoring
python gpu-metrics.py
```
