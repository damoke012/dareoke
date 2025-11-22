# GPU Lab Guide - ROSA/OpenShift

**Duration**: 15 minutes
**Audience**: Developers & Platform Engineers
**Interface**: OpenShift Web Console + CLI

---

## Overview

Learn how to:
- Submit GPU test Jobs to ROSA/OpenShift
- Monitor pod scheduling and execution
- Check logs to verify GPU access
- Run GPU profiling/benchmarking jobs

---

## Prerequisites

1. **OpenShift/ROSA cluster access** with GPU nodes
2. **oc CLI** logged in to the cluster
3. **Namespace** with GPU quota allocated

### Verify Setup

```bash
# Check you're logged in
oc whoami

# Check your project
oc project

# Verify GPU nodes exist (admin access needed)
oc get nodes -l nvidia.com/gpu.present=true
```

---

## Lab Files

| File | Description |
|------|-------------|
| `gpu-test-job.yaml` | Simple GPU detection job using nvidia-smi |
| `gpu-profile-job.yaml` | PyTorch benchmark job for performance testing |
| `gpu_test.py` | Standalone Python GPU test script |

---

## Part 1: Submit GPU Test Job (5 minutes)

### Step 1: Review the Job YAML

Open `gpu-test-job.yaml` and note these key sections:

```yaml
# Resource request - THIS IS REQUIRED
resources:
  limits:
    nvidia.com/gpu: 1  # Request 1 GPU
  requests:
    nvidia.com/gpu: 1

# Tolerations - allows scheduling on GPU nodes
tolerations:
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
```

### Step 2: Submit the Job

```bash
# Apply the job
oc apply -f gpu-test-job.yaml

# Expected output:
# job.batch/gpu-test-job created
```

### Step 3: Watch Pod Creation

```bash
# Watch pods in real-time
oc get pods -w

# Expected progression:
# NAME                  READY   STATUS              RESTARTS   AGE
# gpu-test-job-xxxxx    0/1     Pending             0          1s
# gpu-test-job-xxxxx    0/1     ContainerCreating   0          5s
# gpu-test-job-xxxxx    1/1     Running             0          15s
# gpu-test-job-xxxxx    0/1     Completed           0          25s
```

Press `Ctrl+C` to stop watching once the job completes.

### Step 4: Check Job Status

```bash
# View job status
oc get jobs

# Expected output:
# NAME           COMPLETIONS   DURATION   AGE
# gpu-test-job   1/1           20s        1m
```

### Step 5: View Logs

```bash
# Get the complete output
oc logs job/gpu-test-job
```

**Expected Output:**
```
==============================================
  ROSA GPU TEST JOB
==============================================
Start Time: Wed Nov 20 14:30:00 UTC 2025
Pod Name: gpu-test-job-xxxxx

--- Step 1: Check GPU Availability ---
[Output from nvidia-smi showing GPU details]

--- Step 2: GPU Count ---
Number of GPUs available: 1

--- Step 3: GPU Memory Info ---
index, name, memory.total [MiB], memory.free [MiB]
0, Tesla T4, 15360, 15000

[...]

==============================================
  GPU TEST COMPLETED SUCCESSFULLY
==============================================
```

### Step 6: Check Events

```bash
# View events for the job
oc describe job gpu-test-job

# Look at Events section at the bottom
```

---

## Part 2: Run GPU Profile Job (5 minutes)

### Step 1: Submit Profile Job

```bash
oc apply -f gpu-profile-job.yaml

# Watch it run
oc get pods -l app=gpu-profile -w
```

### Step 2: View Profiling Results

```bash
# Once completed, view logs
oc logs job/gpu-profile-job
```

**Expected Output includes:**
- GPU properties (model, compute capability, memory)
- Memory allocation benchmarks
- Matrix multiplication performance (GFLOPS)
- Memory usage summary

### Step 3: Analyze Results

Look for these key metrics:
- **Compute Capability**: 7.5 for Tesla T4
- **Total Memory**: ~15 GB for T4
- **GFLOPS**: Typically 8-12 TFLOPS for matrix operations

---

## Part 3: Troubleshooting (3 minutes)

### Issue: Pod Stays Pending

```bash
# Check why it's pending
oc describe pod <pod-name>

# Look at Events section for:
# - "Insufficient nvidia.com/gpu" → No available GPU nodes
# - "exceeded quota" → Request quota increase
```

### Issue: ImagePullBackOff

```bash
# Check if the image is accessible
oc describe pod <pod-name>

# May need image pull secret or internal registry
```

### Issue: Container Crashes

```bash
# Check logs for errors
oc logs <pod-name>

# Common causes:
# - nvidia-smi not found → Driver issue
# - CUDA error → Version mismatch
```

### Debug Commands

```bash
# Get all events in namespace
oc get events --sort-by='.lastTimestamp'

# Check GPU resource availability
oc describe node <gpu-node-name> | grep -A 10 "Allocated resources"

# Check quota usage
oc describe quota
```

---

## Part 4: Cleanup (2 minutes)

```bash
# Delete jobs when done
oc delete job gpu-test-job gpu-profile-job

# Verify cleanup
oc get jobs
oc get pods
```

**Note**: Jobs have `ttlSecondsAfterFinished: 300` so they auto-cleanup after 5 minutes.

---

## Administrator Perspective (Optional)

### Using Web Console

1. **Navigate to Workloads → Jobs**
2. **Click Create Job** → Paste YAML
3. **View Job Details** → See pod, status, events
4. **Click Pod** → View logs, metrics, events

### Monitor GPU Usage

```bash
# On GPU node (requires node access)
nvidia-smi dmon -s u

# From any pod with nvidia-smi
watch -n 1 nvidia-smi
```

---

## Key Concepts Summary

| Concept | Description |
|---------|-------------|
| **Job** | Runs once and completes (vs Deployment which runs forever) |
| **nvidia.com/gpu** | Resource type for GPU requests |
| **Tolerations** | Allows pod to run on tainted GPU nodes |
| **nvidia-smi** | NVIDIA tool for GPU info and monitoring |

---

## Comparison: Job vs Deployment for GPU

| Aspect | Job | Deployment |
|--------|-----|------------|
| **Use Case** | One-time tasks, batch jobs, tests | Long-running services, inference APIs |
| **Completion** | Stops when done | Runs indefinitely |
| **Restart** | Never (by design) | Always (self-healing) |
| **GPU Billing** | Only while running | Continuous |

---

## Hands-On Challenges

### Challenge 1: Multi-GPU Job

Modify `gpu-test-job.yaml` to request 2 GPUs:

```yaml
resources:
  limits:
    nvidia.com/gpu: 2
```

Submit and verify both GPUs are detected.

### Challenge 2: Custom GPU Test

Create a job that:
1. Runs a simple PyTorch tensor operation
2. Reports execution time
3. Shows memory usage

### Challenge 3: Compare GPU Types

If your cluster has different GPU types:
1. Submit jobs to different node pools
2. Compare benchmark results
3. Document performance differences

---

## Next Steps

After completing this lab:

1. **Explore GPU Deployments** - For long-running inference services
2. **Try ML Training** - Submit a real training job
3. **Set Up Monitoring** - Prometheus GPU metrics with DCGM
4. **Learn MIG** - Multi-Instance GPU for GPU sharing

---

## Quick Reference

```bash
# Submit job
oc apply -f gpu-test-job.yaml

# Watch pods
oc get pods -w

# View logs
oc logs job/gpu-test-job

# Check job status
oc get jobs

# Describe job
oc describe job gpu-test-job

# Delete job
oc delete job gpu-test-job

# Get events
oc get events --field-selector involvedObject.kind=Job
```

---

## Resources

- [NVIDIA GPU Operator Docs](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/overview.html)
- [OpenShift GPU Support](https://docs.openshift.com/container-platform/latest/architecture/nvidia-gpu-architecture-overview.html)
- [Kubernetes GPU Scheduling](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

---

**Congratulations!** You've completed the GPU Lab. You now know how to submit GPU Jobs, monitor pods, and verify GPU access in ROSA/OpenShift.
