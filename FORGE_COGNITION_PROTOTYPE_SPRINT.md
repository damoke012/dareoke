# Forge Cognition Prototype - 1 Week Sprint Plan

## Goal
Build a working prototype that demonstrates:
1. GPU-accelerated LLM inference on OpenShift
2. TensorRT-LLM optimization pipeline
3. Performance benchmarking (latency, throughput, concurrency)
4. Automated deployment scripts
5. Monitoring & observability

**By end of week**: You'll have hands-on experience with the exact tech stack from the SOW, ready to hit the ground running.

---

## Your Current Infrastructure

| Component | Status | Details |
|-----------|--------|---------|
| ESXi 8.0.2 | ✅ Ready | GPU passthrough configured |
| Tesla P40 | ✅ Ready | 24GB VRAM, passed to ocp-w-1 |
| OpenShift | ✅ Ready | 3 control plane + 3 workers |
| GPU Worker | ✅ Ready | ocp-w-1 with GPU |

---

## Day 1: GPU Operator & Base Infrastructure

### Morning: Install NVIDIA GPU Operator

```bash
# 1. First, verify GPU is visible on ocp-w-1
ssh core@ocp-w-1.lab.ocp.lan "lspci | grep -i nvidia"

# 2. Label the GPU node
oc label node ocp-w-1.lab.ocp.lan nvidia.com/gpu.present=true

# 3. Create namespace for GPU operator
oc create namespace nvidia-gpu-operator

# 4. Install NVIDIA GPU Operator via OperatorHub
# Or via Helm:
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install gpu-operator nvidia/gpu-operator \
  --namespace nvidia-gpu-operator \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true \
  --set dcgmExporter.enabled=true
```

### Afternoon: Verify GPU Operator

```bash
# Check operator pods are running
oc get pods -n nvidia-gpu-operator

# Verify GPU is discovered
oc describe node ocp-w-1.lab.ocp.lan | grep -A5 "Allocatable:" | grep nvidia

# Test GPU access with a simple pod
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0-base
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    nvidia.com/gpu.present: "true"
EOF

# Check the output
oc logs gpu-test
```

### Day 1 Deliverable
- [ ] GPU Operator installed and running
- [ ] GPU visible in OpenShift (nvidia.com/gpu resource)
- [ ] Test pod successfully runs nvidia-smi

---

## Day 2: Deploy Triton Inference Server

### Morning: Set Up Triton

```bash
# Create project for inference
oc new-project forge-inference

# Create PVC for model storage
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-repository
  namespace: forge-inference
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
EOF

# Deploy Triton Inference Server
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: triton-inference-server
  namespace: forge-inference
spec:
  replicas: 1
  selector:
    matchLabels:
      app: triton
  template:
    metadata:
      labels:
        app: triton
    spec:
      nodeSelector:
        nvidia.com/gpu.present: "true"
      containers:
      - name: triton
        image: nvcr.io/nvidia/tritonserver:24.01-trtllm-python-py3
        ports:
        - containerPort: 8000
          name: http
        - containerPort: 8001
          name: grpc
        - containerPort: 8002
          name: metrics
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "32Gi"
          requests:
            memory: "16Gi"
        volumeMounts:
        - name: model-repository
          mountPath: /models
        - name: shm
          mountPath: /dev/shm
        command: ["tritonserver"]
        args:
        - "--model-repository=/models"
        - "--allow-http=true"
        - "--allow-grpc=true"
        - "--allow-metrics=true"
      volumes:
      - name: model-repository
        persistentVolumeClaim:
          claimName: model-repository
      - name: shm
        emptyDir:
          medium: Memory
          sizeLimit: 16Gi
---
apiVersion: v1
kind: Service
metadata:
  name: triton-inference-server
  namespace: forge-inference
spec:
  selector:
    app: triton
  ports:
  - name: http
    port: 8000
    targetPort: 8000
  - name: grpc
    port: 8001
    targetPort: 8001
  - name: metrics
    port: 8002
    targetPort: 8002
EOF
```

### Afternoon: Create Model Repository Structure

```bash
# Get a shell into the Triton pod
oc exec -it deployment/triton-inference-server -n forge-inference -- bash

# Inside the pod, create model repository structure
mkdir -p /models/llm_model/1
```

### Day 2 Deliverable
- [ ] Triton Inference Server deployed
- [ ] Service accessible within cluster
- [ ] Model repository PVC mounted

---

## Day 3: Deploy Small LLM with TensorRT-LLM

### Morning: Build TensorRT-LLM Engine

We'll use a small model (TinyLlama 1.1B) that fits easily on the P40.

```bash
# Create a build job for TensorRT-LLM engine
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: trtllm-build
  namespace: forge-inference
spec:
  template:
    spec:
      nodeSelector:
        nvidia.com/gpu.present: "true"
      restartPolicy: Never
      containers:
      - name: builder
        image: nvcr.io/nvidia/tritonserver:24.01-trtllm-python-py3
        command: ["/bin/bash", "-c"]
        args:
        - |
          set -e
          echo "=== Installing dependencies ==="
          pip install huggingface_hub transformers

          echo "=== Downloading TinyLlama ==="
          python3 -c "
          from huggingface_hub import snapshot_download
          snapshot_download(
              repo_id='TinyLlama/TinyLlama-1.1B-Chat-v1.0',
              local_dir='/models/tinyllama-hf',
              ignore_patterns=['*.bin', '*.h5']  # Get safetensors only
          )
          "

          echo "=== Converting to TensorRT-LLM ==="
          cd /opt/tritonserver/tensorrtllm_backend/tensorrt_llm/examples/llama

          python3 convert_checkpoint.py \
              --model_dir /models/tinyllama-hf \
              --output_dir /models/tinyllama-ckpt \
              --dtype float16

          echo "=== Building TensorRT Engine ==="
          trtllm-build \
              --checkpoint_dir /models/tinyllama-ckpt \
              --output_dir /models/tinyllama-engine \
              --gemm_plugin float16 \
              --max_batch_size 8 \
              --max_input_len 2048 \
              --max_output_len 512

          echo "=== Setting up Triton model repository ==="
          mkdir -p /models/ensemble/1
          mkdir -p /models/preprocessing/1
          mkdir -p /models/postprocessing/1
          mkdir -p /models/tensorrt_llm/1

          # Copy engine to model repo
          cp -r /models/tinyllama-engine/* /models/tensorrt_llm/1/

          echo "=== Build complete ==="
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "32Gi"
          requests:
            memory: "24Gi"
        volumeMounts:
        - name: model-repository
          mountPath: /models
        - name: shm
          mountPath: /dev/shm
      volumes:
      - name: model-repository
        persistentVolumeClaim:
          claimName: model-repository
      - name: shm
        emptyDir:
          medium: Memory
          sizeLimit: 16Gi
  backoffLimit: 1
EOF

# Monitor the build
oc logs -f job/trtllm-build -n forge-inference
```

### Afternoon: Configure Triton Model Repository

```bash
# Create config files for Triton backend
oc exec -it deployment/triton-inference-server -n forge-inference -- bash

# Create tensorrt_llm config
cat > /models/tensorrt_llm/config.pbtxt << 'EOF'
name: "tensorrt_llm"
backend: "tensorrtllm"
max_batch_size: 8

model_transaction_policy {
  decoupled: True
}

input [
  {
    name: "input_ids"
    data_type: TYPE_INT32
    dims: [ -1 ]
  },
  {
    name: "input_lengths"
    data_type: TYPE_INT32
    dims: [ 1 ]
    reshape: { shape: [ ] }
  },
  {
    name: "request_output_len"
    data_type: TYPE_INT32
    dims: [ 1 ]
    reshape: { shape: [ ] }
  }
]

output [
  {
    name: "output_ids"
    data_type: TYPE_INT32
    dims: [ -1, -1 ]
  }
]

instance_group [
  {
    count: 1
    kind: KIND_GPU
    gpus: [ 0 ]
  }
]
EOF
```

### Day 3 Deliverable
- [ ] TinyLlama model downloaded
- [ ] TensorRT-LLM engine built
- [ ] Model configured in Triton

---

## Day 4: Benchmarking Framework

### Morning: Create Benchmark Script

```python
# Save as benchmark_llm.py
import time
import asyncio
import aiohttp
import numpy as np
import json
from dataclasses import dataclass
from typing import List
import argparse

@dataclass
class BenchmarkResult:
    prompt: str
    ttft: float  # Time to first token
    total_time: float
    tokens_generated: int
    tokens_per_second: float

class LLMBenchmark:
    def __init__(self, endpoint: str):
        self.endpoint = endpoint
        self.results: List[BenchmarkResult] = []

    async def single_request(self, session: aiohttp.ClientSession, prompt: str) -> BenchmarkResult:
        payload = {
            "text_input": prompt,
            "max_tokens": 100,
            "temperature": 0.7
        }

        start_time = time.perf_counter()
        first_token_time = None
        tokens = 0

        async with session.post(f"{self.endpoint}/v2/models/ensemble/generate", json=payload) as resp:
            async for chunk in resp.content.iter_chunks():
                if first_token_time is None:
                    first_token_time = time.perf_counter()
                tokens += 1

        end_time = time.perf_counter()

        ttft = (first_token_time - start_time) if first_token_time else 0
        total_time = end_time - start_time
        tps = tokens / total_time if total_time > 0 else 0

        return BenchmarkResult(
            prompt=prompt[:50],
            ttft=ttft,
            total_time=total_time,
            tokens_generated=tokens,
            tokens_per_second=tps
        )

    async def run_concurrent(self, prompts: List[str], concurrency: int) -> dict:
        connector = aiohttp.TCPConnector(limit=concurrency)
        async with aiohttp.ClientSession(connector=connector) as session:
            tasks = [self.single_request(session, p) for p in prompts]
            results = await asyncio.gather(*tasks, return_exceptions=True)

        valid_results = [r for r in results if isinstance(r, BenchmarkResult)]

        return {
            "concurrency": concurrency,
            "total_requests": len(prompts),
            "successful_requests": len(valid_results),
            "ttft_p50": np.percentile([r.ttft for r in valid_results], 50),
            "ttft_p90": np.percentile([r.ttft for r in valid_results], 90),
            "ttft_p99": np.percentile([r.ttft for r in valid_results], 99),
            "latency_p50": np.percentile([r.total_time for r in valid_results], 50),
            "latency_p90": np.percentile([r.total_time for r in valid_results], 90),
            "latency_p99": np.percentile([r.total_time for r in valid_results], 99),
            "avg_tokens_per_second": np.mean([r.tokens_per_second for r in valid_results]),
            "total_throughput": sum([r.tokens_generated for r in valid_results]) / max([r.total_time for r in valid_results], 1)
        }

    def run_benchmark_suite(self, concurrency_levels: List[int] = [1, 2, 4, 8]):
        prompts = [
            "What is machine learning?",
            "Explain neural networks in simple terms.",
            "How does a transformer model work?",
            "What are the benefits of edge computing?",
            "Describe predictive maintenance.",
        ] * 10  # 50 total prompts

        print("=" * 60)
        print("LLM INFERENCE BENCHMARK")
        print("=" * 60)

        all_results = []
        for concurrency in concurrency_levels:
            print(f"\nRunning with concurrency={concurrency}...")
            result = asyncio.run(self.run_concurrent(prompts[:concurrency*5], concurrency))
            all_results.append(result)

            print(f"  TTFT P50: {result['ttft_p50']*1000:.1f}ms")
            print(f"  TTFT P99: {result['ttft_p99']*1000:.1f}ms")
            print(f"  Latency P50: {result['latency_p50']*1000:.1f}ms")
            print(f"  Throughput: {result['total_throughput']:.1f} tokens/sec")

        return all_results

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--endpoint", default="http://triton-inference-server:8000")
    args = parser.parse_args()

    benchmark = LLMBenchmark(args.endpoint)
    results = benchmark.run_benchmark_suite()

    with open("benchmark_results.json", "w") as f:
        json.dump(results, f, indent=2)

    print("\nResults saved to benchmark_results.json")
```

### Afternoon: Create Benchmark Job

```yaml
# benchmark-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: llm-benchmark
  namespace: forge-inference
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: benchmark
        image: python:3.10-slim
        command: ["/bin/bash", "-c"]
        args:
        - |
          pip install aiohttp numpy
          python /scripts/benchmark_llm.py --endpoint http://triton-inference-server:8000
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      volumes:
      - name: scripts
        configMap:
          name: benchmark-scripts
```

### Day 4 Deliverable
- [ ] Benchmark script created
- [ ] Can measure TTFT, latency, throughput
- [ ] Concurrency testing working

---

## Day 5: Deployment Automation

### Morning: Create Deployment Scripts

```bash
# deploy/
# ├── deploy.sh
# ├── rollback.sh
# ├── health_check.sh
# ├── configs/
# │   └── values.yaml
# └── manifests/
#     ├── namespace.yaml
#     ├── pvc.yaml
#     ├── triton-deployment.yaml
#     └── service.yaml
```

**deploy.sh**:
```bash
#!/bin/bash
set -e

NAMESPACE=${NAMESPACE:-forge-inference}
MODEL_NAME=${MODEL_NAME:-tinyllama}

echo "=== Deploying Forge Inference Stack ==="

# Create namespace
oc apply -f manifests/namespace.yaml

# Create PVC
oc apply -f manifests/pvc.yaml

# Deploy Triton
oc apply -f manifests/triton-deployment.yaml

# Create service
oc apply -f manifests/service.yaml

# Wait for deployment
echo "Waiting for Triton to be ready..."
oc rollout status deployment/triton-inference-server -n $NAMESPACE --timeout=300s

# Health check
./health_check.sh

echo "=== Deployment Complete ==="
```

**health_check.sh**:
```bash
#!/bin/bash
NAMESPACE=${NAMESPACE:-forge-inference}
TRITON_POD=$(oc get pod -n $NAMESPACE -l app=triton -o jsonpath='{.items[0].metadata.name}')

echo "Checking Triton health..."

# Check HTTP health endpoint
oc exec -n $NAMESPACE $TRITON_POD -- curl -s localhost:8000/v2/health/ready

# Check GPU is being used
oc exec -n $NAMESPACE $TRITON_POD -- nvidia-smi

# Check model is loaded
oc exec -n $NAMESPACE $TRITON_POD -- curl -s localhost:8000/v2/models/tensorrt_llm/ready

echo "Health check passed!"
```

### Afternoon: Create Monitoring

```yaml
# prometheus-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: triton-metrics
  namespace: forge-inference
spec:
  selector:
    matchLabels:
      app: triton
  endpoints:
  - port: metrics
    interval: 15s
    path: /metrics
```

### Day 5 Deliverable
- [ ] Deployment scripts created
- [ ] Health checks automated
- [ ] Basic monitoring configured

---

## Day 6: Optimization Experiments

### Morning: Quantization Experiments

```bash
# Build INT8 quantized model
trtllm-build \
    --checkpoint_dir /models/tinyllama-ckpt \
    --output_dir /models/tinyllama-engine-int8 \
    --gemm_plugin float16 \
    --use_smooth_quant \
    --per_token \
    --per_channel \
    --max_batch_size 8

# Compare performance
# Run benchmark with FP16 model
# Run benchmark with INT8 model
# Document results
```

### Afternoon: Batching Optimization

```bash
# Test different batch sizes
for BATCH in 1 2 4 8 16; do
    echo "Testing batch size: $BATCH"
    # Rebuild engine with different max_batch_size
    # Run benchmarks
    # Record results
done
```

### Day 6 Deliverable
- [ ] INT8 quantization tested
- [ ] Batching experiments completed
- [ ] Performance comparison documented

---

## Day 7: Documentation & Demo

### Morning: Create Documentation

```markdown
# Forge Cognition Inference Platform - Prototype

## Architecture
- NVIDIA GPU Operator on OpenShift
- Triton Inference Server with TensorRT-LLM backend
- TinyLlama 1.1B model (optimized)

## Performance Results
| Metric | FP16 | INT8 |
|--------|------|------|
| TTFT P50 | XXms | XXms |
| TTFT P99 | XXms | XXms |
| Throughput | XX tok/s | XX tok/s |
| Max Concurrent | X | X |

## Deployment
./deploy.sh

## Benchmarking
./run_benchmark.sh
```

### Afternoon: Prepare Demo

```bash
# Create simple demo script
curl -X POST http://triton-inference-server:8000/v2/models/ensemble/generate \
  -H "Content-Type: application/json" \
  -d '{
    "text_input": "What is predictive maintenance?",
    "max_tokens": 100
  }'
```

### Day 7 Deliverable
- [ ] Documentation complete
- [ ] Demo script ready
- [ ] Performance results documented

---

## Quick Start Commands

### Day 1 Kickoff
```bash
# Uncordon GPU node and verify
oc adm uncordon ocp-w-1.lab.ocp.lan
oc get nodes

# SSH to verify GPU
ssh core@ocp-w-1.lab.ocp.lan "lspci | grep -i nvidia"
```

### Monitor Progress
```bash
# Watch GPU usage
ssh core@ocp-w-1.lab.ocp.lan "watch nvidia-smi"

# Watch pods
oc get pods -n forge-inference -w

# Check Triton logs
oc logs -f deployment/triton-inference-server -n forge-inference
```

---

## Expected Outcomes

By end of week, you'll have:

1. **Working GPU infrastructure** on OpenShift
2. **Deployed LLM** with TensorRT-LLM optimization
3. **Benchmarking framework** measuring SOW KPIs
4. **Deployment automation** scripts
5. **Hands-on experience** with exact Honeywell tech stack

This puts you **weeks ahead** of the project timeline and gives you credibility in the discovery meeting.

---

## Files to Create

```
forge-cognition-prototype/
├── README.md
├── deploy/
│   ├── deploy.sh
│   ├── rollback.sh
│   ├── health_check.sh
│   └── manifests/
│       ├── namespace.yaml
│       ├── gpu-operator/
│       ├── triton/
│       └── monitoring/
├── benchmark/
│   ├── benchmark_llm.py
│   ├── run_benchmark.sh
│   └── results/
├── models/
│   └── configs/
└── docs/
    ├── architecture.md
    ├── deployment.md
    └── benchmarking.md
```
