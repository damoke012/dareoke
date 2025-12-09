# K3s Deployment for Honeywell Forge Cognition

Lightweight Kubernetes (K3s) deployment with GPU time-slicing, failover, and graceful degradation.

## Why K3s?

| Feature | Docker Compose | K3s |
|---------|---------------|-----|
| GPU Time-Slicing | No | Yes |
| Auto-restart on failure | Basic | Advanced (probes) |
| Resource quotas | No | Yes |
| Priority/Preemption | No | Yes |
| Rolling updates | Manual | Automatic |
| Health checks | Basic | Liveness/Readiness/Startup |
| Metrics integration | Manual | Native |

## Quick Start

```bash
# 1. Install K3s with GPU support
sudo ./scripts/install-k3s.sh

# 2. Deploy Forge Cognition
./scripts/deploy-forge.sh

# 3. Test the deployment
curl http://localhost:30080/health
```

## What Gets Installed

1. **K3s** - Lightweight Kubernetes (single binary, ~50MB)
2. **NVIDIA Container Toolkit** - GPU container runtime
3. **NVIDIA Device Plugin** - GPU resource management
4. **Time-Slicing Config** - GPU partitioning (4 virtual GPUs by default)

## GPU Time-Slicing

Time-slicing creates multiple "virtual GPUs" from one physical GPU:

```
┌─────────────────────────────────────────────────────────────┐
│                    Physical GPU (24GB)                      │
├─────────────────────────────────────────────────────────────┤
│  Time Slice 1   │  Time Slice 2   │  Time Slice 3  │  ...  │
│  (Pod A)        │  (Pod B)        │  (Pod C)       │       │
│  nvidia.com/gpu │  nvidia.com/gpu │  nvidia.com/gpu│       │
└─────────────────────────────────────────────────────────────┘
```

**Configuration** (in `config/time-slicing-config.yaml`):
```yaml
sharing:
  timeSlicing:
    resources:
      - name: nvidia.com/gpu
        replicas: 4  # 4 virtual GPUs
```

**Recommended replicas by SKU:**
| SKU | GPU Memory | Recommended Replicas |
|-----|------------|---------------------|
| Jetson Thor | 128GB | 4-8 |
| RTX Pro 4000 | 20GB | 2-4 |
| Tesla P40 | 24GB | 2-4 |

## Failover & Health Checks

The deployment includes three types of probes:

```yaml
# Startup probe - for slow model loading (up to 5 min)
startupProbe:
  httpGet:
    path: /health
  failureThreshold: 30
  periodSeconds: 10

# Liveness probe - restart if unhealthy
livenessProbe:
  httpGet:
    path: /health
  failureThreshold: 3
  periodSeconds: 30

# Readiness probe - remove from service if not ready
readinessProbe:
  httpGet:
    path: /health/ready
  failureThreshold: 3
  periodSeconds: 10
```

**Failover behavior:**
1. Pod becomes unhealthy → Removed from Service (no traffic)
2. Liveness check fails 3x → Pod restarted
3. New pod starts → Startup probe allows model loading time
4. Readiness passes → Pod added back to Service

## Priority Classes

LLM inference gets highest priority:

| Priority Class | Value | Use Case |
|---------------|-------|----------|
| `forge-llm-critical` | 1,000,000 | LLM inference |
| `forge-high` | 100,000 | Milvus, embeddings |
| `forge-normal` | 10,000 | Monitoring, logging |
| `forge-low` | 1,000 | Batch jobs |

If resources are scarce, lower-priority pods get preempted.

## Resource Quotas

Prevents resource exhaustion:

```yaml
hard:
  requests.nvidia.com/gpu: "4"  # Max 4 GPU slices
  requests.memory: "32Gi"
  limits.memory: "64Gi"
  pods: "10"
```

## Directory Structure

```
k3s-deployment/
├── scripts/
│   ├── install-k3s.sh      # Full installation
│   ├── uninstall-k3s.sh    # Clean removal
│   └── deploy-forge.sh     # Deploy manifests
├── manifests/
│   ├── namespace.yaml
│   ├── inference-deployment.yaml
│   ├── inference-configmap.yaml
│   ├── storage.yaml
│   ├── priority-class.yaml
│   ├── resource-quota.yaml
│   ├── pod-disruption-budget.yaml
│   ├── hpa-gpu.yaml
│   └── network-policy.yaml
├── config/
│   └── time-slicing-config.yaml
└── README.md
```

## Common Operations

### Check GPU allocation
```bash
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
```

### View inference server logs
```bash
kubectl logs -f deployment/inference-server -n forge-cognition
```

### Scale replicas (if GPU slices available)
```bash
kubectl scale deployment/inference-server -n forge-cognition --replicas=2
```

### Check GPU metrics
```bash
kubectl exec -it deployment/inference-server -n forge-cognition -- nvidia-smi
```

### Restart inference server
```bash
kubectl rollout restart deployment/inference-server -n forge-cognition
```

### Update configuration
```bash
kubectl edit configmap inference-config -n forge-cognition
kubectl rollout restart deployment/inference-server -n forge-cognition
```

## Troubleshooting

### Pod stuck in Pending
```bash
kubectl describe pod -n forge-cognition -l app=inference-server
```
Common causes:
- No GPU available (check `nvidia.com/gpu` allocatable)
- Resource quota exceeded
- PVC not bound

### GPU not detected
```bash
# Check NVIDIA runtime
kubectl get runtimeclass nvidia

# Check device plugin
kubectl get pods -n nvidia-device-plugin

# Test GPU access
kubectl run gpu-test --rm -it --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","containers":[{"name":"gpu-test","image":"nvidia/cuda:12.2.0-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' \
  --restart=Never
```

### Model loading timeout
Increase startup probe timeout:
```yaml
startupProbe:
  failureThreshold: 60  # 10 minutes
  periodSeconds: 10
```

## Air-Gapped Deployment

For environments without internet:

```bash
# On internet-connected machine:
# 1. Download K3s binary
curl -Lo k3s https://github.com/k3s-io/k3s/releases/download/v1.28.4%2Bk3s1/k3s

# 2. Save container images
docker pull nvidia/k8s-device-plugin:v0.14.3
docker save nvidia/k8s-device-plugin:v0.14.3 -o device-plugin.tar

# 3. Transfer to air-gapped machine

# On air-gapped machine:
# 1. Install K3s binary
chmod +x k3s && mv k3s /usr/local/bin/
k3s server &

# 2. Load images
ctr -n k8s.io images import device-plugin.tar
```

## Comparison with Docker Compose

When to use each:

| Scenario | Recommendation |
|----------|---------------|
| Simple prototype | Docker Compose |
| Production with failover | K3s |
| GPU time-slicing needed | K3s |
| Resource isolation required | K3s |
| Air-gapped with minimal overhead | Docker Compose |
| Multiple workloads sharing GPU | K3s |
