# GPU Time-Slicing in OpenShift

## Overview

GPU time-slicing allows multiple workloads to share a single physical GPU by dividing processing time into short, alternating time slots. It uses CUDA time-slicing to multiplex workloads from replicas of the same underlying GPU.

### Key Characteristics
- **No memory or fault isolation** between replicas (unlike MIG)
- Ideal for **lightweight inference, data preprocessing, and smaller workloads**
- Improves GPU utilization when full isolation isn't needed
- Risk of out-of-memory issues if workloads aren't controlled

---

## GPU Sharing Strategies Comparison

| Strategy | Isolation | Best For | GPU Support |
|----------|-----------|----------|-------------|
| **Time-Slicing** | None (shared memory) | Lightweight workloads, inference | All NVIDIA GPUs |
| **MIG (Multi-Instance GPU)** | Full memory & fault isolation | Production, mixed workloads | A100, A30, H100 only |
| **MPS (Multi-Process Service)** | Partial | Parallel GPU workloads | Most NVIDIA GPUs |

---

## Configuration Steps

### Prerequisites
- NVIDIA GPU Operator installed
- GPU nodes available in cluster
- Cluster admin access

### Step 1: Enable GPU Feature Discovery

```bash
oc patch clusterpolicy gpu-cluster-policy -n nvidia-gpu-operator \
    --type json \
    --patch '[{"op": "replace", "path": "/spec/gfd/enable", "value": true}]'
```

### Step 2: Create Time-Slicing ConfigMap

Create a ConfigMap that defines how many replicas (slices) each GPU type should have:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: device-plugin-config
  namespace: nvidia-gpu-operator
data:
  # Tesla T4 Configuration - 8 slices per GPU
  Tesla-T4: |-
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: true
        resources:
          - name: nvidia.com/gpu
            replicas: 8

  # A100 40GB Configuration - 8 slices per GPU
  A100-SXM4-40GB: |-
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: true
        resources:
          - name: nvidia.com/gpu
            replicas: 8

  # A100 80GB Configuration - 8 slices per GPU
  A100-SXM4-80GB: |-
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: true
        resources:
          - name: nvidia.com/gpu
            replicas: 8
```

Apply the ConfigMap:
```bash
oc apply -f device-plugin-config.yaml
```

### Step 3: Link ConfigMap to ClusterPolicy

```bash
oc patch clusterpolicy gpu-cluster-policy \
    -n nvidia-gpu-operator --type merge \
    -p '{"spec": {"devicePlugin": {"config": {"name": "device-plugin-config"}}}}'
```

### Step 4: Label GPU Nodes

Apply the time-slicing configuration to nodes based on GPU type:

```bash
# For Tesla T4 nodes
oc label --overwrite node \
    --selector=nvidia.com/gpu.product=Tesla-T4 \
    nvidia.com/device-plugin.config=Tesla-T4

# For A100 40GB nodes
oc label --overwrite node \
    --selector=nvidia.com/gpu.product=A100-SXM4-40GB \
    nvidia.com/device-plugin.config=A100-SXM4-40GB

# For A100 80GB nodes
oc label --overwrite node \
    --selector=nvidia.com/gpu.product=A100-SXM4-80GB \
    nvidia.com/device-plugin.config=A100-SXM4-80GB
```

### Step 5: Verify Configuration

Check that the GPU capacity now shows the replicas:

```bash
# Check node capacity
oc get node --selector=nvidia.com/gpu.product=Tesla-T4-SHARED \
    -o json | jq '.items[0].status.capacity'
```

Expected output:
```json
{
  "nvidia.com/gpu": "8"
}
```

Check allocatable GPUs:
```bash
oc describe node <gpu-node-name> | grep -A5 "Allocatable:"
```

---

## Using Time-Sliced GPUs in Workloads

### Pod Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  containers:
  - name: cuda-app
    image: nvidia/cuda:12.0-base
    resources:
      limits:
        nvidia.com/gpu: "1"    # Requests 1 time-slice
```

### Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inference-service
spec:
  replicas: 4    # 4 pods sharing GPUs via time-slicing
  selector:
    matchLabels:
      app: inference
  template:
    metadata:
      labels:
        app: inference
    spec:
      containers:
      - name: inference
        image: my-inference-image:latest
        resources:
          limits:
            nvidia.com/gpu: "1"
          requests:
            nvidia.com/gpu: "1"
```

### RHOAI Workbench Example

When creating workbenches in OpenShift AI, request 1 GPU - it will receive a time-slice:

```yaml
resources:
  limits:
    nvidia.com/gpu: "1"
    memory: "16Gi"
    cpu: "4"
  requests:
    nvidia.com/gpu: "1"
    memory: "8Gi"
    cpu: "2"
```

---

## MachineSet Integration (Auto-scaling)

For auto-scaled GPU nodes, apply time-slicing config to the MachineSet:

```bash
oc patch machineset worker-gpu-nvidia-t4-us-east-1a \
    -n openshift-machine-api --type merge \
    --patch '{"spec": {"template": {"spec": {"metadata": {"labels": {"nvidia.com/device-plugin.config": "Tesla-T4"}}}}}}'
```

This ensures new GPU nodes automatically get time-slicing enabled.

---

## Configuration Options

### renameByDefault

| Value | Behavior |
|-------|----------|
| `false` | Adds "-SHARED" suffix to GPU product label (e.g., `Tesla-T4-SHARED`) |
| `true` | Keeps original GPU product label |

Recommendation: Use `false` to make it clear which nodes have time-slicing enabled.

### failRequestsGreaterThanOne

| Value | Behavior |
|-------|----------|
| `true` | Rejects pod requests for more than 1 GPU replica |
| `false` | Allows requests for multiple replicas |

Recommendation: Use `true` to prevent confusion about resource allocation.

---

## Monitoring Time-Sliced GPUs

### Check GPU Utilization

```bash
# On the GPU node
nvidia-smi

# Or via pod
oc exec -it <gpu-pod> -- nvidia-smi
```

### Check GPU Allocation

```bash
oc describe node <gpu-node> | grep -A10 "Allocated resources:"
```

### View GPU Pods

```bash
oc get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | {name: .metadata.name, namespace: .metadata.namespace, gpu: .spec.containers[].resources.limits."nvidia.com/gpu"}'
```

---

## Best Practices

1. **Workload Sizing**: Time-slicing works best for small, bursty workloads. Large training jobs should use dedicated GPUs or MIG.

2. **Memory Management**: Monitor GPU memory usage - all time-sliced workloads share the same GPU memory.

3. **Replicas**: Start with 4-8 replicas per GPU. Adjust based on workload patterns.

4. **Isolation**: If you need memory/fault isolation, use MIG instead (A100/A30/H100 only).

5. **Security**: Upgrade to GPU Operator v24.6.2+ for critical security fixes.

---

## Troubleshooting

### GPUs Not Showing Replicas

```bash
# Check device plugin pods
oc get pods -n nvidia-gpu-operator | grep device-plugin

# Check device plugin logs
oc logs -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset
```

### Pods Stuck Pending

```bash
# Check if GPU resources are available
oc describe node <gpu-node> | grep -A5 "Allocated resources:"

# Check pod events
oc describe pod <pending-pod>
```

### ConfigMap Not Applied

```bash
# Verify ConfigMap exists
oc get configmap device-plugin-config -n nvidia-gpu-operator

# Check ClusterPolicy
oc get clusterpolicy gpu-cluster-policy -o yaml | grep -A5 "devicePlugin:"
```

---

## References

- [NVIDIA GPU Operator - Time-slicing GPUs in OpenShift (Latest)](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/time-slicing-gpus-in-openshift.html)
- [Red Hat Blog - Sharing is caring: GPU time-slicing](https://www.redhat.com/en/blog/sharing-caring-how-make-most-your-gpus-part-1-time-slicing)
- [Red Hat OpenShift AI - About GPU Time Slicing](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/2.25/html/working_with_accelerators/about-gpu-time-slicing_accelerators)
- [NVIDIA GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/index.html)
