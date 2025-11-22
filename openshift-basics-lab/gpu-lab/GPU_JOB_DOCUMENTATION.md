# GPU Test Job Documentation

**Duration: 5 minutes**

## Overview

The `gpu-test-job.yaml` is a Kubernetes Job that validates GPU availability and performance on OpenShift/ROSA clusters with NVIDIA GPU nodes.

---

## How It Works

### Architecture Overview

1. **Kubelet creates an emptyDir volume** - Temporary storage on the node
2. **Init container clones code from Git** - Downloads scripts to the emptyDir
3. **Volume is mounted to main container** - Scripts available at `/scripts`
4. **Main container runs the code** - Executes the GPU test

### Why Use This Pattern?

- **Separation of concerns** - Code stored in Git, not embedded in YAML
- **Version control** - Update scripts without modifying the Job YAML
- **Clean YAML** - Job definition remains simple and readable
- **Reusability** - Same init container pattern works for any code

---

## Prerequisites: Push Code to Git

Before deploying the Job, the GPU test scripts must be in your Git repository.

### Step 1: Create the Scripts

The scripts are located at:
- `openshift-basics-lab/gpu-lab/scripts/gpu_test.py` - Python GPU benchmark
- `openshift-basics-lab/gpu-lab/scripts/run_test.sh` - Bash runner script

### Step 2: Push to Git Repository

```bash
git add openshift-basics-lab/gpu-lab/scripts/
git commit -m "Add GPU test scripts"
git push
```

### Step 3: Verify Scripts Are Available

The init container will clone from:
```
https://github.com/damoke012/dareoke.git
```

And copy scripts from:
```
openshift-basics-lab/gpu-lab/scripts/
```

---

## Init Container Explained

The init container is the key to this pattern. It runs **before** the main container and prepares the environment.

### What the Init Container Does

```yaml
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
```

1. **`git clone --depth 1`** - Shallow clone (only latest commit, faster)
2. **`cp ... /scripts/`** - Copy scripts to the shared emptyDir volume
3. **`chmod +x`** - Make shell scripts executable

### How the Main Container Gets Access

Both containers mount the same `emptyDir` volume:

```yaml
volumes:
- name: scripts
  emptyDir: {}
```

- **Init container** writes to `/scripts` (emptyDir)
- **Main container** reads from `/scripts` (same emptyDir)
- The volume persists for the pod's lifetime

### Execution Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Pod Created   │ --> │  Init Container │ --> │  Main Container │
│                 │     │  (git-clone)    │     │   (gpu-test)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │                        │
                               v                        v
                        Clone from Git           Run /scripts/run_test.sh
                        Copy to /scripts         Execute gpu_test.py
```

---

## The Complete YAML File

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

---

## What This YAML Does

1. **Detects GPU hardware** using `nvidia-smi`
2. **Checks CUDA availability** through PyTorch
3. **Runs matrix multiplication benchmark** to measure GPU performance
4. **Reports TFLOPS** (Tera Floating Point Operations per Second)

---

## YAML Structure Breakdown

### Metadata
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-job
  labels:
    app: gpu-test
    demo: rosa-gpu-lab
```
- **Kind: Job** - Runs once to completion (not continuously like a Deployment)
- **Labels** - Used for identification and filtering

### Job Spec
```yaml
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
```
- **backoffLimit: 0** - Don't retry on failure
- **ttlSecondsAfterFinished: 300** - Auto-delete job 5 minutes after completion

### Container Configuration
```yaml
containers:
- name: gpu-test
  image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
```
- Uses official **PyTorch image with CUDA 12.1** support
- Includes cuDNN for optimized GPU operations

### GPU Resource Requests
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
- **nvidia.com/gpu: 1** - Requests exactly 1 GPU
- Memory and CPU limits prevent resource contention

### GPU Tolerations
```yaml
tolerations:
- key: "nvidia.com/gpu"
  operator: "Exists"
  effect: "NoSchedule"
```
- Allows pod to schedule on GPU nodes that have taints
- Required when GPU nodes are tainted to prevent non-GPU workloads

### Security Context
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
```
- Follows OpenShift security best practices
- Drops unnecessary Linux capabilities

---

## How to Deploy via OpenShift Console

### Step 1: Navigate to Import YAML
1. Open **OpenShift Console**
2. Select your project/namespace from the dropdown
3. Click the **+** (Import YAML) button in the top navigation bar

### Step 2: Paste and Create
1. Copy the complete YAML above
2. Paste it into the YAML editor
3. Click **Create**

### Step 3: Verify Job Creation
1. Go to **Workloads → Jobs**
2. You should see `gpu-test-job` in the list
3. Status will show **Running** then **Complete**

---

## Monitoring the Job

### Check Job Status
1. **Workloads → Jobs** → Click on `gpu-test-job`
2. View:
   - **Status**: Running, Complete, or Failed
   - **Completions**: 1/1 when done
   - **Duration**: How long it ran

### View Logs
1. **Workloads → Jobs** → `gpu-test-job`
2. Click on the **Pods** tab
3. Click on the pod name (e.g., `gpu-test-job-xxxxx`)
4. Go to **Logs** tab
5. View real-time output from the GPU test

### Check Metrics
1. **Observe → Metrics**
2. Useful queries:
   - `container_cpu_usage_seconds_total{pod=~"gpu-test-job.*"}` - CPU usage
   - `container_memory_working_set_bytes{pod=~"gpu-test-job.*"}` - Memory usage
3. For GPU metrics (if DCGM exporter is installed):
   - `DCGM_FI_DEV_GPU_UTIL` - GPU utilization %
   - `DCGM_FI_DEV_FB_USED` - GPU memory used

### Check Events
1. **Workloads → Jobs** → `gpu-test-job`
2. Click **Events** tab
3. Look for:
   - `Scheduled` - Pod assigned to node
   - `Pulled` - Image downloaded
   - `Started` - Container running
   - `Completed` - Job finished

---

## What Can Happen During Execution

### Successful Run
- Job completes in 30-60 seconds
- Logs show `GPU TEST COMPLETED SUCCESSFULLY`
- TFLOPS value displayed (e.g., 2.40 TFLOPS)

### Common Issues and How to Check

#### 1. Pod Stuck in Pending
**Symptom**: Job shows "Pending" for extended time

**How to Check**:
1. Go to **Workloads → Pods**
2. Click on the pending pod
3. Check **Events** tab for messages like:
   - `0/5 nodes are available: 5 Insufficient nvidia.com/gpu`
   - `pod didn't trigger scale-up`

**Cause**: No GPU nodes available or all GPUs in use

#### 2. ImagePullBackOff
**Symptom**: Pod shows "ImagePullBackOff" status

**How to Check**:
1. **Workloads → Pods** → Click pod → **Events**
2. Look for: `Failed to pull image`

**Cause**: Cannot download PyTorch image (network/registry issue)

#### 3. CrashLoopBackOff
**Symptom**: Pod keeps restarting

**How to Check**:
1. View pod **Logs** for error messages
2. Check if `nvidia-smi` fails

**Cause**: GPU driver issue or CUDA mismatch

#### 4. OOMKilled (Out of Memory)
**Symptom**: Pod terminated unexpectedly

**How to Check**:
1. **Workloads → Pods** → Click pod
2. Look at **Status**: `OOMKilled`

**Cause**: Matrix size too large for GPU memory

#### 5. Job Failed
**Symptom**: Job status shows "Failed"

**How to Check**:
1. **Workloads → Jobs** → `gpu-test-job`
2. Check **Conditions** section
3. View pod logs for error details

---

## Expected Output

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

---

## Cleanup

Jobs auto-delete after 5 minutes (`ttlSecondsAfterFinished: 300`), or manually:

1. **Workloads → Jobs**
2. Click the three dots menu next to `gpu-test-job`
3. Select **Delete Job**

---

## Quick Reference

| What to Check | Where in Console |
|---------------|------------------|
| Job Status | Workloads → Jobs → gpu-test-job |
| Pod Logs | Workloads → Pods → [pod-name] → Logs |
| Events | Workloads → Jobs → gpu-test-job → Events |
| Metrics | Observe → Metrics |
| GPU Node Status | Compute → Nodes → Filter by GPU label |

---

## Related Files

- `gpu-profile-job.yaml` - More detailed GPU profiling with multiple benchmarks
- `gpu-stress-test.yaml` - Extended stress testing for GPU stability
