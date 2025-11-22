# GPU Profiling Setup for OpenShift

**Duration: 10 minutes**

## Overview

This guide covers how to set up GPU profiling and monitoring in OpenShift clusters with NVIDIA GPUs.

---

## Option 1: Use Existing DCGM Exporter (Recommended)

If the NVIDIA GPU Operator is installed, DCGM Exporter is likely already running cluster-wide.

### Check if DCGM is already deployed:
```bash
oc get pods -A | grep dcgm
```

Expected output shows pods in `nvidia-gpu-operator` namespace:
```
nvidia-gpu-operator   nvidia-dcgm-exporter-xxx   1/1   Running   0   5d
```

If already deployed, skip to **Accessing GPU Metrics** section.

---

## Option 2: Deploy DCGM Exporter (Requires Admin)

If DCGM is not deployed, use the following YAML. **Note:** This requires cluster admin privileges for SCC permissions.

### Prerequisites
Ask cluster admin to grant SCC:
```bash
oc adm policy add-scc-to-user nvidia-dcgm-exporter -z dcgm-exporter -n <your-namespace>
```

### dcgm-exporter.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dcgm-exporter
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dcgm-exporter
  labels:
    app: dcgm-exporter
spec:
  selector:
    matchLabels:
      app: dcgm-exporter
  template:
    metadata:
      labels:
        app: dcgm-exporter
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9400"
    spec:
      serviceAccountName: dcgm-exporter
      containers:
      - name: dcgm-exporter
        image: nvcr.io/nvidia/k8s/dcgm-exporter:3.3.0-3.2.0-ubuntu22.04
        ports:
        - name: metrics
          containerPort: 9400
        securityContext:
          runAsNonRoot: false
          runAsUser: 0
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
        volumeMounts:
        - name: pod-gpu-resources
          mountPath: /var/lib/kubelet/pod-resources
          readOnly: true
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      nodeSelector:
        nvidia.com/gpu.present: "true"
      volumes:
      - name: pod-gpu-resources
        hostPath:
          path: /var/lib/kubelet/pod-resources
---
apiVersion: v1
kind: Service
metadata:
  name: dcgm-exporter
  labels:
    app: dcgm-exporter
spec:
  type: ClusterIP
  ports:
  - name: metrics
    port: 9400
    targetPort: 9400
  selector:
    app: dcgm-exporter
```

### Deploy:
```bash
oc apply -f dcgm-exporter.yaml -n <your-namespace>
```

---

## Accessing GPU Metrics

### Available Metrics

DCGM Exporter provides these Prometheus metrics:

| Metric | Description |
|--------|-------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization % |
| `DCGM_FI_DEV_MEM_COPY_UTIL` | Memory copy utilization % |
| `DCGM_FI_DEV_FB_FREE` | Free framebuffer memory (MB) |
| `DCGM_FI_DEV_FB_USED` | Used framebuffer memory (MB) |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature (C) |
| `DCGM_FI_DEV_POWER_USAGE` | Power usage (W) |
| `DCGM_FI_DEV_SM_CLOCK` | SM clock speed (MHz) |
| `DCGM_FI_DEV_MEM_CLOCK` | Memory clock speed (MHz) |

### Query in Prometheus

Example PromQL queries:

```promql
# GPU utilization by GPU UUID
DCGM_FI_DEV_GPU_UTIL

# Memory usage in GB
DCGM_FI_DEV_FB_USED / 1024

# Average GPU temperature
avg(DCGM_FI_DEV_GPU_TEMP)

# Power consumption by node
sum by (Hostname) (DCGM_FI_DEV_POWER_USAGE)
```

---

## Quick Profiling Methods

### 1. nvidia-smi (In Workbench)

```bash
# Basic status
nvidia-smi

# Continuous monitoring (every 1 second)
nvidia-smi dmon -s u

# Query specific metrics
nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw --format=csv -l 1
```

### 2. PyTorch Profiler (In Notebook)

```python
import torch
from torch.profiler import profile, ProfilerActivity

# Profile GPU operations
with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    record_shapes=True,
    profile_memory=True
) as prof:
    # Your model code here
    x = torch.randn(1000, 1000).cuda()
    y = torch.matmul(x, x)

# Print results
print(prof.key_averages().table(sort_by="cuda_time_total", row_limit=10))

# Export for TensorBoard
prof.export_chrome_trace("trace.json")
```

### 3. Memory Tracking

```python
import torch

# Check current memory usage
print(f"Allocated: {torch.cuda.memory_allocated() / 1e9:.2f} GB")
print(f"Cached: {torch.cuda.memory_reserved() / 1e9:.2f} GB")

# Get max memory used
print(f"Max allocated: {torch.cuda.max_memory_allocated() / 1e9:.2f} GB")

# Reset stats
torch.cuda.reset_peak_memory_stats()
```

---

## Grafana Dashboard

### Import GPU Dashboard

1. Open Grafana
2. Go to **Dashboards > Import**
3. Use dashboard ID: **12239** (NVIDIA DCGM Exporter Dashboard)
4. Select your Prometheus data source
5. Click Import

### Custom Panel Examples

**GPU Utilization Graph:**
```json
{
  "title": "GPU Utilization",
  "type": "timeseries",
  "targets": [
    {
      "expr": "DCGM_FI_DEV_GPU_UTIL",
      "legendFormat": "GPU {{gpu}}"
    }
  ]
}
```

**Memory Usage Gauge:**
```json
{
  "title": "GPU Memory Used",
  "type": "gauge",
  "targets": [
    {
      "expr": "DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_FREE + DCGM_FI_DEV_FB_USED) * 100",
      "legendFormat": "GPU {{gpu}}"
    }
  ]
}
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| DCGM pods not starting | Check SCC permissions with cluster admin |
| No metrics in Prometheus | Verify ServiceMonitor or prometheus.io annotations |
| nvidia-smi not found | Check GPU driver installation on node |
| Permission denied | Run workbench with GPU tolerations |

---

## Related Files

- [gpu-test-job.yaml](gpu-test-job.yaml) - Quick GPU validation job
- [GPU_JOB_DOCUMENTATION.md](GPU_JOB_DOCUMENTATION.md) - GPU test job details
