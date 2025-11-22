# OpenShift Basics Lab Guide

This guide walks you through deploying workloads, monitoring, and troubleshooting in OpenShift using the **Administrator UI** (no terminal commands).

---

## Part 1: Understanding the GPU Job YAML

### What is a Job?

A **Job** is a Kubernetes workload that runs a task to completion. Unlike Deployments (which run continuously), Jobs are designed for batch processing, one-time tasks, or computations that have a definite end.

### GPU Test Job Structure

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-job
  labels:
    app: gpu-test
    demo: rosa-gpu-lab
```

**Metadata Section:**
- `name`: Unique identifier for this Job
- `labels`: Tags for organizing and filtering resources

```yaml
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
```

**Job Spec:**
- `backoffLimit: 0` - Don't retry if the Job fails
- `ttlSecondsAfterFinished: 300` - Auto-delete completed Job after 5 minutes

```yaml
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: gpu-test
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
```

**Pod Template:**
- `restartPolicy: Never` - Don't restart the container (required for Jobs)
- `image` - PyTorch container with CUDA support for GPU computation

```yaml
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "4Gi"
            cpu: "2"
          requests:
            nvidia.com/gpu: 1
            memory: "2Gi"
            cpu: "1"
```

**Resource Requests/Limits:**
- `nvidia.com/gpu: 1` - Request 1 GPU from the cluster
- `requests` - Minimum resources guaranteed
- `limits` - Maximum resources allowed

```yaml
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"
```

**Tolerations:**
- Allows the Pod to schedule on GPU nodes that have taints
- GPU nodes are often tainted to prevent non-GPU workloads from using them

### What This Job Does

1. **Checks GPU availability** using `nvidia-smi`
2. **Reports GPU info** (name, memory, CUDA version)
3. **Runs actual GPU computation**:
   - Creates 3000x3000 matrices on the GPU
   - Performs 20 matrix multiplications
   - Calculates and reports TFLOPS performance
4. **Completes and exits** (Job finishes)

---

## Part 2: Running the GPU Job via UI

### Step 1: Navigate to Jobs

1. Log into OpenShift Console
2. Select your **Project** from the dropdown (top left)
3. Go to **Workloads** → **Jobs**

### Step 2: Create the Job

1. Click **Create Job** (or **+** button)
2. Select **YAML view**
3. Delete any existing content
4. Paste the GPU Job YAML content
5. Click **Create**

### Step 3: Monitor Job Execution

1. You'll see the Job in the list with status **Running**
2. Click on the Job name (`gpu-test-job`) to see details
3. Go to the **Pods** tab to see the created Pod
4. Click on the Pod name to view details

### Step 4: View Job Logs

1. From the Pod details page, go to **Logs** tab
2. You'll see output like:
   ```
   === Step 1: Check GPU Availability ===
   [SUCCESS] GPUs detected!

   === Step 3: Running GPU Computation ===
   PyTorch version: 2.1.0
   CUDA available: True
   GPU device: NVIDIA A100-SXM4-40GB

   === Results ===
   Matrix size: 3000x3000
   TFLOPS: 12.34
   ```

### Step 5: Check Job Completion

1. Go back to **Workloads** → **Jobs**
2. Status should show **SuccessCriteriaMet** with `1` succeeded pod
3. The Job will auto-delete after 5 minutes (ttlSecondsAfterFinished)

---

## Part 3: Understanding the Deployment YAML

### What is a Deployment?

A **Deployment** manages long-running applications. It:
- Keeps Pods running continuously
- Handles restarts if containers fail
- Allows scaling (multiple replicas)

### Key Deployment Features

```yaml
spec:
  replicas: 2
```
- Runs 2 identical Pods for high availability

```yaml
      initContainers:
      - name: init-setup
        image: registry.access.redhat.com/ubi8/ubi-minimal:latest
```

**Init Containers:**
- Run **before** the main container starts
- Used for setup tasks (config files, data initialization)
- Must complete successfully before main container starts

```yaml
      volumes:
      - name: shared-data
        emptyDir: {}
```

**Volumes:**
- `emptyDir` creates temporary storage shared between containers
- Init container writes config, main container reads it

---

## Part 4: Running the Deployment via UI

### Step 1: Navigate to Deployments

1. Go to **Workloads** → **Deployments**
2. Click **Create Deployment**

### Step 2: Create the Deployment

1. Select **YAML view**
2. Paste the Deployment YAML content
3. Click **Create**

### Step 3: Watch Deployment Progress

1. Click on `web-service` deployment
2. Go to **Pods** tab
3. You'll see Pods with status:
   - **Init:0/1** - Init container running
   - **Running** - Main container started

### Step 4: View Init Container Logs

1. Click on a Pod name
2. Go to **Logs** tab
3. Use the **Container** dropdown to select `init-setup`
4. You'll see:
   ```
   INIT CONTAINER: Preparing environment
   ✓ Dependencies verified
   ✓ Configuration created
   ✓ Data initialized
   INIT CONTAINER COMPLETED
   ```

### Step 5: View Main Container Logs

1. Switch to `web` container in the dropdown
2. You'll see:
   ```
   DEPLOYMENT: Web Service Started
   Loading configuration from init container...
   APP_VERSION=1.0.0
   ✓ Configuration loaded successfully

   [timestamp] Heartbeat - Pod web-service-xxx is healthy
   ```

### Step 6: Scale the Deployment

1. Go to **Workloads** → **Deployments**
2. Click the **⋮** menu next to `web-service`
3. Select **Edit Pod count**
4. Change to desired number (e.g., 3)
5. Click **Save**

---

## Part 5: Setting Up Alerts and Monitoring

### Viewing Metrics

#### Pod Metrics

1. Go to **Workloads** → **Pods**
2. Click on a Pod name
3. Go to **Metrics** tab
4. View graphs for:
   - **CPU Usage**
   - **Memory Usage**
   - **Network I/O**
   - **Filesystem**

#### Project Metrics

1. Go to **Observe** → **Metrics**
2. Enter a PromQL query, for example:
   - `sum(container_memory_usage_bytes{namespace="your-project"})` - Total memory
   - `sum(rate(container_cpu_usage_seconds_total{namespace="your-project"}[5m]))` - CPU rate

### Setting Up Alerts

#### Step 1: Navigate to Alerts

1. Go to **Observe** → **Alerting**
2. Click **Alerting Rules** tab

#### Step 2: Create Alert Rule

1. Click **Create Alert Rule**
2. Configure the alert:

**Example: High Memory Alert**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: high-memory-alert
  namespace: your-project
spec:
  groups:
  - name: memory-alerts
    rules:
    - alert: HighMemoryUsage
      expr: |
        (container_memory_usage_bytes{namespace="your-project"} /
         container_spec_memory_limit_bytes{namespace="your-project"}) > 0.8
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage detected"
        description: "Pod {{ $labels.pod }} is using more than 80% of memory limit"
```

3. Click **Create**

#### Step 3: View Active Alerts

1. Go to **Observe** → **Alerting**
2. **Alerts** tab shows currently firing alerts
3. Click on an alert for details and affected resources

### Viewing Dashboards

1. Go to **Observe** → **Dashboards**
2. Select a dashboard:
   - **Kubernetes / Compute Resources / Namespace (Pods)**
   - **Kubernetes / Compute Resources / Pod**
3. Select your namespace/pod from dropdowns

---

## Part 6: Checking Logs

### Pod Logs

1. Go to **Workloads** → **Pods**
2. Click on the Pod name
3. Go to **Logs** tab

**Log Features:**
- **Container dropdown** - Select which container (for multi-container Pods)
- **Wrap lines** - Toggle line wrapping
- **Timestamps** - Show/hide timestamps
- **Download** - Save logs to file
- **Follow** - Auto-scroll to new logs

### Aggregated Logs (if configured)

1. Go to **Observe** → **Logs**
2. Filter by:
   - Namespace
   - Pod name
   - Container
   - Time range
3. Search for specific text

### Events

1. Go to **Home** → **Events**
2. Filter by namespace
3. Events show:
   - Pod scheduling
   - Container starts/stops
   - Errors and warnings
   - Resource issues

---

## Part 7: Troubleshooting Common Issues

### Issue: Pod Stuck in Pending

**Check Events:**
1. Click on the Pod
2. Go to **Events** tab
3. Look for messages like:
   - `Insufficient nvidia.com/gpu` - No GPUs available
   - `Insufficient memory` - Not enough memory in cluster
   - `Unschedulable` - No nodes match requirements

**Resolution:**
- Check resource requests are realistic
- Verify GPU nodes exist and are available
- Check node taints and tolerations

### Issue: Pod in CrashLoopBackOff

**Check Logs:**
1. Click on the Pod
2. Go to **Logs** tab
3. Look for error messages

**Check Previous Container:**
1. In Logs tab, check **Previous container** option
2. See why previous instance crashed

**Common Causes:**
- Application error (check logs)
- Insufficient memory (OOMKilled)
- Missing dependencies
- Configuration errors

### Issue: Init Container Failed

**Check Init Container Logs:**
1. Click on the Pod
2. Go to **Logs** tab
3. Select the init container from dropdown

**Pod Status Shows:**
- `Init:Error` - Init container failed
- `Init:CrashLoopBackOff` - Init container keeps failing

### Issue: High Resource Usage

**Check Metrics:**
1. Click on the Pod
2. Go to **Metrics** tab
3. Identify which resource is high

**Resolution:**
- Increase resource limits
- Optimize application code
- Scale horizontally (more replicas)

### Issue: Job Failed

**Check Job Details:**
1. Go to **Workloads** → **Jobs**
2. Click on the Job
3. Check **Conditions** section for failure reason

**Check Pod Logs:**
1. Go to **Pods** tab
2. Click on the failed Pod
3. View **Logs** and **Events**

---

## Part 8: Cleanup

### Delete Job

1. Go to **Workloads** → **Jobs**
2. Click **⋮** menu next to the Job
3. Select **Delete Job**
4. Confirm deletion

### Delete Deployment

1. Go to **Workloads** → **Deployments**
2. Click **⋮** menu next to the Deployment
3. Select **Delete Deployment**
4. Confirm deletion

---

## Quick Reference

| Task | Navigation |
|------|------------|
| Create Job | Workloads → Jobs → Create Job |
| Create Deployment | Workloads → Deployments → Create Deployment |
| View Logs | Workloads → Pods → [Pod] → Logs |
| View Metrics | Workloads → Pods → [Pod] → Metrics |
| Check Events | Home → Events |
| Set Alerts | Observe → Alerting → Create Alert Rule |
| View Dashboards | Observe → Dashboards |
| Scale Deployment | Workloads → Deployments → [Deployment] → ⋮ → Edit Pod count |

---

## Summary

In this lab you learned:

1. **Jobs** - Run one-time batch tasks (like GPU computation)
2. **Deployments** - Run long-running services with init containers
3. **Monitoring** - View metrics and create alerts
4. **Logging** - Access container logs for debugging
5. **Troubleshooting** - Diagnose common Pod issues

All operations were performed through the **OpenShift Administrator UI** without using the terminal.
