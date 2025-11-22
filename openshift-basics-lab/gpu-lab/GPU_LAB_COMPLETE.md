# GPU Lab - Complete Guide

This guide covers GPU testing, profiling, and alerting for OpenShift/ROSA clusters.

---

## GPU Test Job

### The Complete GPU Test Job YAML

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-job
  labels:
    app: gpu-test
    demo: rosa-gpu-lab
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app: gpu-test
    spec:
      restartPolicy: Never
      # Init container pulls code from Git to shared volume
      initContainers:
      - name: git-clone
        image: alpine/git:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          git clone --depth 1 https://github.com/damoke012/dareoke.git /tmp/repo
          cp /tmp/repo/openshift-basics-lab/gpu-lab/scripts/* /scripts/
          chmod +x /scripts/*.sh
        volumeMounts:
        - name: scripts
          mountPath: /scripts
      # Main container runs the GPU test
      containers:
      - name: gpu-test
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command: ["/bin/bash", "/scripts/run_test.sh"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "4Gi"
            cpu: "2"
          requests:
            nvidia.com/gpu: 1
            memory: "2Gi"
            cpu: "1"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      volumes:
      - name: scripts
        emptyDir: {}
```

### GPU Test Job Overview

The `gpu-test-job.yaml` is a Kubernetes Job that validates GPU availability and performance on OpenShift/ROSA clusters with NVIDIA GPU nodes.

**What This YAML Does:**
1. Detects GPU hardware using `nvidia-smi`
2. Checks CUDA availability through PyTorch
3. Runs matrix multiplication benchmark to measure GPU performance
4. Reports TFLOPS (Tera Floating Point Operations per Second)

### How to Deploy via OpenShift Console

**Step 1: Navigate to OpenShift Console**
1. Open OpenShift Console
2. Select your project/namespace from the dropdown

**Step 2: Paste and Create**
1. Go to **Workloads → Jobs**
2. Click **Create Job**
3. Delete the YAML and paste your YAML manifest
4. Click **Create**

**Step 3: Verify Job Creation**
1. Go to **Workloads → Jobs**
2. You should see `gpu-test-job` in the list
3. Status will show **Running** then **Complete**

### Monitoring the Job

**Check Job Status:**
1. **Workloads → Jobs** → Click on `gpu-test-job`
2. View:
   - Status: Running, Complete, or Failed
   - Completions: 1/1 when done
   - Duration: How long it ran

**View Logs:**
1. **Workloads → Jobs** → `gpu-test-job`
2. Click on the **Pods** tab
3. Click on the pod name (e.g., `gpu-test-job-xxxxx`)
4. Go to **Logs** tab
5. View real-time output from the GPU test

**Check Metrics:**
1. **Workloads → Jobs** → `gpu-test-job`
2. Click on the **Pods** tab
3. Click on the pod name (e.g., `gpu-test-job-xxxxx`)
4. Go to **Metrics**
   - Memory usage
   - CPU usage
   - Filesystem
   - Network in
   - Network out

**Check Events:**
1. **Workloads → Jobs** → `gpu-test-job`
2. Click **Events** tab
3. Look for:
   - Scheduled - Pod assigned to node
   - Pulled - Image downloaded
   - Started - Container running
   - Completed - Job finished

### Common Issues

| Issue | Symptom | How to Check | Cause |
|-------|---------|--------------|-------|
| Pod Stuck in Pending | Job shows "Pending" | Events tab: "Insufficient nvidia.com/gpu" | No GPU nodes available |
| ImagePullBackOff | Pod shows "ImagePullBackOff" | Events: "Failed to pull image" | Network/registry issue |
| CrashLoopBackOff | Pod keeps restarting | View Logs for errors | GPU driver or CUDA mismatch |
| OOMKilled | Pod terminated | Status shows "OOMKilled" | Matrix too large for GPU memory |
| Job Failed | Status shows "Failed" | Check Conditions and logs | Various - check logs |

### Expected Output

```
==============================================
  ROSA GPU TEST JOB
==============================================
Start Time: Fri Nov 22 10:30:00 UTC 2025
Pod Name: gpu-test-job-abc123

--- Step 1: Check GPU Availability ---
[SUCCESS] GPUs detected!

--- Step 2: GPU Memory Info ---
index, name, memory.total, memory.free
0, NVIDIA A10G, 23028 MiB, 22515 MiB

--- Step 3: Running GPU Computation ---
PyTorch version: 2.1.0
CUDA available: True
GPU device: NVIDIA A10G

=== Results ===
Matrix size: 3000x3000
Operations: 20 matrix multiplications
Total time: 0.45 seconds
TFLOPS: 2.40

GPU computation completed successfully!
==============================================
  GPU TEST COMPLETED SUCCESSFULLY
==============================================
```

### Cleanup

Jobs auto-delete after 5 minutes (`ttlSecondsAfterFinished: 300`), or manually:
1. **Workloads → Jobs**
2. Click the three dots menu next to `gpu-test-job`
3. Select **Delete Job**

---

## GPU Profiling Deployment

### The Complete GPU Profiling Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-profiler
  labels:
    app: gpu-profiler
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gpu-profiler
  template:
    metadata:
      labels:
        app: gpu-profiler
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8000"
    spec:
      # Init container pulls code from Git
      initContainers:
      - name: git-clone
        image: alpine/git:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          git clone --depth 1 https://github.com/damoke012/dareoke.git /tmp/repo
          cp -r /tmp/repo/openshift-basics-lab/gpu-lab/profiler/* /app/
          chmod +x /app/*.py
        volumeMounts:
        - name: app-code
          mountPath: /app
      containers:
      - name: gpu-profiler
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command: ["python", "/app/profiler_service.py"]
        ports:
        - name: metrics
          containerPort: 8000
        volumeMounts:
        - name: app-code
          mountPath: /app
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "8Gi"
            cpu: "4"
          requests:
            nvidia.com/gpu: 1
            memory: "4Gi"
            cpu: "2"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        env:
        - name: PROMETHEUS_PORT
          value: "8000"
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
      volumes:
      - name: app-code
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: gpu-profiler
  labels:
    app: gpu-profiler
spec:
  ports:
  - name: metrics
    port: 8000
    targetPort: 8000
  selector:
    app: gpu-profiler
```

### What the Profiler Code Does

The `profiler_service.py` creates a simple HTTP server that exposes GPU metrics in Prometheus format.

**How It Works:**
1. Starts HTTP server on port 8000
2. Exposes `/metrics` endpoint with GPU stats
3. Exposes `/health` endpoint for health checks

**Metrics It Collects:**

| Metric | Source | Description |
|--------|--------|-------------|
| `gpu_memory_allocated_gb` | PyTorch | Currently allocated GPU memory |
| `gpu_memory_reserved_gb` | PyTorch | Reserved GPU memory (cache) |
| `gpu_memory_total_gb` | PyTorch | Total GPU memory |
| `gpu_info` | PyTorch | Device name, compute capability |
| `gpu_utilization_percent` | nvidia-smi | GPU compute utilization |
| `gpu_memory_utilization_percent` | nvidia-smi | Memory bandwidth utilization |
| `gpu_temperature_celsius` | nvidia-smi | GPU temperature |
| `gpu_power_watts` | nvidia-smi | Power consumption |

**How Prometheus Scrapes It:**

The Deployment has these annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8000"
```

Prometheus auto-discovers and scrapes `/metrics` every 15-30 seconds.

**Example Output:**

When you hit `http://gpu-profiler:8000/metrics`:
```
gpu_memory_allocated_gb{gpu="0"} 0.52
gpu_memory_reserved_gb{gpu="0"} 2.00
gpu_memory_total_gb{gpu="0"} 40.00
gpu_info{gpu="0",name="NVIDIA A100-SXM4-40GB",compute_capability="8.0"} 1
gpu_utilization_percent{gpu="0"} 45
gpu_memory_utilization_percent{gpu="0"} 23
gpu_temperature_celsius{gpu="0"} 52
gpu_power_watts{gpu="0"} 125.50
```

This lets you create Grafana dashboards and alerts based on real-time GPU metrics from your workloads.

### Why We Need a Service

The Deployment creates pods that expose metrics on port 8000, but pods have dynamic IPs that change when they restart. The **Service** provides:
- A stable DNS name (`gpu-profiler`) and IP address
- Load balancing across pod replicas
- Service discovery for Prometheus to scrape metrics

Without the Service, Prometheus wouldn't know how to find the metrics endpoint.

### How to Deploy

**Note:** The YAML contains two resources (Deployment + Service). Use **Import YAML** to deploy both at once.

1. Click the **+** button in top navigation (Import YAML)
2. Paste the complete YAML above
3. Click **Create**

**Alternative - Deploy Separately:**

**Step 1: Create Deployment**
1. **Workloads → Deployments → Create Deployment**
2. Paste only the Deployment section (before the `---`)
3. Click **Create**

**Step 2: Create Service**
1. **Networking → Services → Create Service**
2. Paste the Service section:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: gpu-profiler
  labels:
    app: gpu-profiler
spec:
  ports:
  - name: metrics
    port: 8000
    targetPort: 8000
  selector:
    app: gpu-profiler
```
3. Click **Create**

### Verify Deployment

1. **Workloads → Deployments** → `gpu-profiler` - should show 1/1 Running
2. **Networking → Services** → `gpu-profiler` - should show port 8000
3. View pod **Logs** for profiler output

---

## GPU Alerts

### The Complete GPU Alerts YAML

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gpu-alerts
  labels:
    release: prometheus
spec:
  groups:
  - name: gpu-alerts
    rules:
    # Alert: GPU utilization is high (>80% for 5 minutes)
    - alert: GPUHighUtilization
      expr: DCGM_FI_DEV_GPU_UTIL > 80
      for: 5m
      labels:
        severity: warning
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} high utilization"
        description: "GPU {{ $labels.gpu }} on {{ $labels.Hostname }} has been above 80% utilization for 5 minutes. Current: {{ $value }}%"

    # Alert: GPU memory is almost full (>90%)
    - alert: GPUMemoryHigh
      expr: (DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_FREE + DCGM_FI_DEV_FB_USED)) * 100 > 90
      for: 2m
      labels:
        severity: critical
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} memory critical"
        description: "GPU {{ $labels.gpu }} memory usage is above 90%. Current: {{ $value | printf \"%.1f\" }}%"

    # Alert: GPU temperature is high (>80°C)
    - alert: GPUTemperatureHigh
      expr: DCGM_FI_DEV_GPU_TEMP > 80
      for: 3m
      labels:
        severity: warning
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} temperature high"
        description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C, above 80°C threshold"

    # Alert: GPU temperature critical (>90°C)
    - alert: GPUTemperatureCritical
      expr: DCGM_FI_DEV_GPU_TEMP > 90
      for: 1m
      labels:
        severity: critical
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} temperature critical"
        description: "GPU {{ $labels.gpu }} temperature is {{ $value }}°C - immediate action required!"

    # Alert: GPU power usage high (>300W)
    - alert: GPUPowerHigh
      expr: DCGM_FI_DEV_POWER_USAGE > 300
      for: 5m
      labels:
        severity: warning
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} power usage high"
        description: "GPU {{ $labels.gpu }} power consumption is {{ $value }}W"

    # Alert: No GPUs detected (for testing - fires when GPU util is 0)
    - alert: GPUIdleTest
      expr: DCGM_FI_DEV_GPU_UTIL == 0
      for: 1m
      labels:
        severity: info
        team: gpu-lab
      annotations:
        summary: "GPU {{ $labels.gpu }} is idle"
        description: "GPU {{ $labels.gpu }} has 0% utilization - this alert fires for testing Google Chat integration"
```

### How to Deploy Alerts

1. **Search → PrometheusRule** (or navigate via Administration)
2. Click **Create PrometheusRule**
3. Paste the YAML above
4. Click **Create**

### Verify Alerts

1. Open **Grafana** → **Alerting → Alert rules**
2. You should see the GPU alerts listed
3. The `GPUIdleTest` alert will fire when GPUs are idle (0% utilization) - use this to test Google Chat notifications

### Test Alert Flow

1. Deploy the alerts YAML
2. Wait 1 minute for `GPUIdleTest` to fire (when no GPU workload running)
3. Check **Grafana → Alerting → Alert rules** - should show "Firing"
4. Check Google Chat - notification should arrive

---

## Quick Reference

| Task | Location |
|------|----------|
| Deploy GPU Test Job | Workloads → Jobs → Create Job |
| Deploy GPU Profiler | Workloads → Deployments → Create Deployment |
| Deploy GPU Alerts | Search → PrometheusRule → Create |
| View Job Logs | Workloads → Jobs → [job] → Pods → [pod] → Logs |
| View Alerts | Grafana → Alerting → Alert rules |
| View GPU Metrics | Grafana → Explore → Query DCGM metrics |

---

## Files in This Lab

| File | Purpose |
|------|---------|
| `gpu-test-job.yaml` | GPU validation job |
| `scripts/run_test.sh` | GPU test script (pulled from Git) |
| `profiler/profiler_service.py` | GPU profiling service (pulled from Git) |
| `GPU_LAB_COMPLETE.md` | This documentation |
