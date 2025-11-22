# OpenShift Basics Lab - Step-by-Step Guide

## Overview
This lab demonstrates the difference between **Jobs** (run-once tasks) and **Deployments** (always-running services) in OpenShift. You'll store Python code in cloud storage (PersistentVolumeClaim) and run it using OpenShift workloads.

**What You'll Learn:**
- How to store code in OpenShift cloud storage
- Difference between Jobs and Deployments
- How to create workloads via the OpenShift UI
- How to view logs and metrics

**Time Required:** 30-45 minutes

---

## Prerequisites

- Access to OpenShift cluster
- Project/namespace created (e.g., `basics-lab`)
- Web browser access to OpenShift console

---

# Step 1: Save Code to Local Storage

First, create the Python scripts that will run in your workloads.

## 1.1 Create Directory Structure

Create a folder on your local machine:
```
basics-lab/
├── process_data.py
├── web_server.py
├── pvc-storage.yaml
├── job.yaml
└── deployment.yaml
```

## 1.2 Create `process_data.py`

This script runs once and processes data (used by the Job).

**File: `process_data.py`**

```python
#!/usr/bin/env python3
"""
Simple data processing script for demonstration.
This simulates fetching data, processing it, and generating a report.
"""

import time
import sys
from datetime import datetime

def main():
    print("=" * 60)
    print("DATA PROCESSING JOB")
    print("=" * 60)
    print(f"Start Time: {datetime.now()}")
    print()

    # Step 1: Load data
    print("Step 1: Loading data from source...")
    time.sleep(2)
    records = 1000
    print(f"✓ Loaded {records} records")
    print()

    # Step 2: Process data
    print("Step 2: Processing data in batches...")
    batches = 5
    for i in range(1, batches + 1):
        print(f"  Processing batch {i}/{batches}...")
        time.sleep(1)
    print(f"✓ Processed all {batches} batches")
    print()

    # Step 3: Generate report
    print("Step 3: Generating report...")
    time.sleep(1)
    success = 995
    errors = 5
    print(f"✓ Report generated")
    print()

    # Results
    print("RESULTS:")
    print(f"  Total Records: {records}")
    print(f"  Successful: {success}")
    print(f"  Errors: {errors}")
    print(f"  Success Rate: {(success/records)*100:.1f}%")
    print()

    print(f"End Time: {datetime.now()}")
    print("=" * 60)
    print("JOB COMPLETED SUCCESSFULLY")
    print("=" * 60)

    return 0

if __name__ == "__main__":
    sys.exit(main())
```

## 1.3 Create `web_server.py`

This script runs continuously like a web service (used by the Deployment).

**File: `web_server.py`**

```python
#!/usr/bin/env python3
"""
Simple web service simulation for demonstration.
This keeps running and reports status periodically.
"""

import time
import random
import socket
from datetime import datetime

def main():
    hostname = socket.gethostname()

    print("=" * 60)
    print("WEB SERVICE STARTED")
    print("=" * 60)
    print(f"Pod: {hostname}")
    print(f"Start Time: {datetime.now()}")
    print()
    print("Service is running and ready to handle requests...")
    print()

    # Keep running forever (like a web server)
    while True:
        connections = random.randint(10, 50)
        memory = random.randint(30, 70)
        cpu = random.randint(20, 80)

        print(f"[{datetime.now()}] Heartbeat - Pod {hostname} is healthy")
        print(f"[{datetime.now()}] Active connections: {connections}")
        print(f"[{datetime.now()}] Memory usage: {memory}%")
        print(f"[{datetime.now()}] CPU usage: {cpu}%")
        print("---")

        time.sleep(30)

if __name__ == "__main__":
    main()
```

---

# Step 2: Create YAML Files

Create three YAML files that define your cloud storage and workloads.

## 2.1 Create Cloud Storage (PVC)

This creates a persistent volume to store your Python scripts.

**File: `pvc-storage.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: code-storage
  labels:
    app: demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: gp3-csi
```

**What this does:**
- Creates 1GB of persistent storage
- Named `code-storage`
- Uses AWS EBS (gp3-csi) storage class

## 2.2 Create Job YAML

This defines a Job that runs the data processing script once.

**File: `job.yaml`**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processing-job
  labels:
    app: demo
spec:
  template:
    spec:
      restartPolicy: Never

      volumes:
      - name: code-storage
        persistentVolumeClaim:
          claimName: code-storage

      containers:
      - name: processor
        image: registry.access.redhat.com/ubi9/python-39:latest
        command: ["python3"]
        args: ["/mnt/code-storage/process_data.py"]

        volumeMounts:
        - name: code-storage
          mountPath: /mnt/code-storage

        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

**Key Points:**
- `restartPolicy: Never` - Don't restart after completion (this makes it a Job)
- Mounts `code-storage` PVC at `/mnt/code-storage`
- Runs `python3 /mnt/code-storage/process_data.py`

## 2.3 Create Deployment YAML

This defines a Deployment that runs the web service continuously.

**File: `deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-service
  labels:
    app: demo
spec:
  replicas: 2

  selector:
    matchLabels:
      app: demo

  template:
    metadata:
      labels:
        app: demo
    spec:
      volumes:
      - name: code-storage
        persistentVolumeClaim:
          claimName: code-storage

      containers:
      - name: web
        image: registry.access.redhat.com/ubi9/python-39:latest
        command: ["python3"]
        args: ["/mnt/code-storage/web_server.py"]

        volumeMounts:
        - name: code-storage
          mountPath: /mnt/code-storage

        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"

        livenessProbe:
          exec:
            command:
            - /bin/bash
            - -c
            - echo "healthy"
          initialDelaySeconds: 5
          periodSeconds: 10
```

**Key Points:**
- `replicas: 2` - Runs 2 copies for high availability
- No `restartPolicy` specified - defaults to `Always` (keeps running)
- `livenessProbe` - Health check to restart if unhealthy
- Runs `python3 /mnt/code-storage/web_server.py`

---

# Step 3: Create Resources via OpenShift UI

Now let's create everything in the OpenShift web console.

## 3.1 Access OpenShift Console

1. Open your OpenShift cluster URL in a web browser
2. Log in with your credentials
3. Select your project (e.g., `basics-lab`) from the dropdown at the top

## 3.2 Create the PersistentVolumeClaim

**Steps:**

1. Click **"Administrator"** view (left sidebar)
2. Navigate to **Storage → PersistentVolumeClaims**
3. Click **"Create PersistentVolumeClaim"** (blue button, top right)
4. Click **"Edit YAML"** (top right)
5. **Delete all the template content**
6. **Copy and paste** the contents of `pvc-storage.yaml`
7. Click **"Create"** (bottom)

**Expected Result:**
- You'll see `code-storage` PVC with status "Bound"
- Size: 1 GiB
- Access Mode: RWO (ReadWriteOnce)

## 3.3 Upload Python Scripts to PVC

We need to copy the Python scripts into the PVC storage.

**Steps:**

1. Navigate to **Workloads → Pods**
2. Click **"+ Create Pod"** (blue button, top right)
3. Click **"Edit YAML"**
4. Paste this temporary helper pod YAML:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: upload-helper
spec:
  volumes:
  - name: code-storage
    persistentVolumeClaim:
      claimName: code-storage
  containers:
  - name: uploader
    image: registry.access.redhat.com/ubi9/python-39:latest
    command: ["/bin/bash", "-c", "sleep infinity"]
    volumeMounts:
    - name: code-storage
      mountPath: /mnt/code-storage
```

5. Click **"Create"**
6. Wait for pod to show **"Running"** status
7. Click on the **"upload-helper"** pod name
8. Click the **"Terminal"** tab
9. In the terminal, create the Python scripts:

**Create process_data.py:**
```bash
cat > /mnt/code-storage/process_data.py << 'EOF'
[Paste the entire process_data.py content here]
EOF
```

**Create web_server.py:**
```bash
cat > /mnt/code-storage/web_server.py << 'EOF'
[Paste the entire web_server.py content here]
EOF
```

10. Verify files were created:
```bash
ls -lh /mnt/code-storage/
```

11. Go back to **Workloads → Pods**
12. Click the **three dots** (⋮) next to `upload-helper`
13. Click **"Delete Pod"**

## 3.4 Create the Job

**Steps:**

1. Navigate to **Workloads → Jobs**
2. Click **"Create Job"** (blue button, top right)
3. Click **"Edit YAML"**
4. **Delete all template content**
5. **Copy and paste** the contents of `job.yaml`
6. Click **"Create"**

**Expected Result:**
- Job named `data-processing-job` appears
- Status will show "Running" then "Complete"
- Duration: ~8-10 seconds

## 3.5 Create the Deployment

**Steps:**

1. Navigate to **Workloads → Deployments**
2. Click **"Create Deployment"** (blue button, top right)
3. Click **"Edit YAML"**
4. **Delete all template content**
5. **Copy and paste** the contents of `deployment.yaml`
6. Click **"Create"**

**Expected Result:**
- Deployment named `web-service` appears
- Status: 2/2 pods ready
- Replicas: 2/2

---

# Step 4: Check Logs in the UI

## 4.1 View Job Logs

**Steps:**

1. Navigate to **Workloads → Jobs**
2. Click on **"data-processing-job"**
3. Click the **"Pods"** tab
4. Click on the pod name (e.g., `data-processing-job-xxxxx`)
5. Click the **"Logs"** tab

**What You'll See:**
```
============================================================
DATA PROCESSING JOB
============================================================
Start Time: 2025-11-18 10:00:00.123456

Step 1: Loading data from source...
✓ Loaded 1000 records

Step 2: Processing data in batches...
  Processing batch 1/5...
  Processing batch 2/5...
  Processing batch 3/5...
  Processing batch 4/5...
  Processing batch 5/5...
✓ Processed all 5 batches

Step 3: Generating report...
✓ Report generated

RESULTS:
  Total Records: 1000
  Successful: 995
  Errors: 5
  Success Rate: 99.5%

End Time: 2025-11-18 10:00:08.456789
============================================================
JOB COMPLETED SUCCESSFULLY
============================================================
```

**Key Observations:**
- Job shows start and end time (duration ~8 seconds)
- Clear beginning and end
- Job pod stays in "Completed" status after finishing

## 4.2 View Deployment Logs

**Steps:**

1. Navigate to **Workloads → Deployments**
2. Click on **"web-service"**
3. Click the **"Pods"** tab
4. Click on **one of the pod names** (e.g., `web-service-xxxxx-yyyyy`)
5. Click the **"Logs"** tab

**What You'll See:**
```
============================================================
WEB SERVICE STARTED
============================================================
Pod: web-service-7d8f9c5b4-abc12
Start Time: 2025-11-18 10:00:00.123456

Service is running and ready to handle requests...

[2025-11-18 10:00:00.456789] Heartbeat - Pod web-service-7d8f9c5b4-abc12 is healthy
[2025-11-18 10:00:00.456790] Active connections: 27
[2025-11-18 10:00:00.456791] Memory usage: 45%
[2025-11-18 10:00:00.456792] CPU usage: 62%
---
[2025-11-18 10:00:30.456789] Heartbeat - Pod web-service-7d8f9c5b4-abc12 is healthy
[2025-11-18 10:00:30.456790] Active connections: 38
[2025-11-18 10:00:30.456791] Memory usage: 52%
[2025-11-18 10:00:30.456792] CPU usage: 71%
---
[continues forever...]
```

**Key Observations:**
- Logs show continuous heartbeat every 30 seconds
- No end time - keeps running forever
- Different pod names show different hostnames
- Logs keep growing (use "Follow" checkbox to see real-time updates)

## 4.3 Compare Logs from Multiple Deployment Pods

**Steps:**

1. Go back to **Deployments → web-service → Pods** tab
2. Open logs for the **second pod** (different name)
3. Notice each pod has a different hostname in its logs

**Key Observation:**
- Both pods run the same code but have unique identities
- Demonstrates load balancing across replicas

---

# Step 5: Validate Metrics in the UI

## 5.1 Job Metrics

**Steps:**

1. Navigate to **Workloads → Jobs**
2. Click on **"data-processing-job"**
3. Look at the **Details** tab

**Metrics to Observe:**

| Metric | Value | What It Means |
|--------|-------|---------------|
| **Status** | Complete | Job finished successfully |
| **Completions** | 1/1 | 1 successful run out of 1 desired |
| **Duration** | ~8-10s | Time from start to completion |
| **Pods Statuses** | 0 Active, 1 Succeeded, 0 Failed | Pod completed successfully |
| **Backoff Limit** | 2 | Will retry up to 2 times if it fails |

**To See Timeline:**
1. Click **"Events"** tab
2. See events like:
   - `Created pod: data-processing-job-xxxxx`
   - `Started container processor`
   - `Pod completed successfully`

## 5.2 Deployment Metrics

**Steps:**

1. Navigate to **Workloads → Deployments**
2. Click on **"web-service"**
3. Look at the **Details** tab

**Metrics to Observe:**

| Metric | Value | What It Means |
|--------|-------|---------------|
| **Status** | 2 of 2 pods | Both replicas running healthy |
| **Replicas** | Desired: 2, Current: 2, Ready: 2 | All pods ready |
| **Strategy** | RollingUpdate | Updates pods one at a time (zero downtime) |
| **Age** | Time since created | How long Deployment has been running |

**Pod-Level Metrics:**

1. Click **"Pods"** tab
2. For each pod, observe:

| Metric | What It Shows |
|--------|---------------|
| **Status** | Running (green dot) |
| **Restarts** | 0 (if no crashes) |
| **Age** | How long pod has been running |
| **CPU** | Current CPU usage (e.g., 5m = 0.005 cores) |
| **Memory** | Current memory usage (e.g., 45Mi) |

**Resource Usage:**

1. Click on a pod name
2. Click **"Metrics"** tab (if available)
3. See graphs for:
   - CPU usage over time
   - Memory usage over time

## 5.3 Test Self-Healing (Deployment)

**Steps:**

1. Navigate to **Workloads → Deployments → web-service → Pods**
2. Click the **three dots** (⋮) next to one pod
3. Click **"Delete Pod"**
4. Watch what happens:
   - Pod goes to "Terminating"
   - **Immediately**, a new pod starts creating
   - Within seconds, new pod is "Running"
   - Deployment maintains 2/2 replicas

**Metric to Observe:**
- **Restarts**: Will remain 0 (deletion creates new pod, not restart)
- **Age**: New pod shows recent creation time
- **Pod Name**: New pod has different random suffix

**Key Observation:**
- Deployment ensures 2 replicas always running (self-healing)
- Jobs don't do this - once complete, they stay complete

## 5.4 Test Scaling (Deployment)

**Steps:**

1. Navigate to **Workloads → Deployments**
2. Click on **"web-service"**
3. Click **"Actions"** dropdown (top right)
4. Click **"Edit Pod count"**
5. Change from `2` to `3`
6. Click **"Save"**

**Watch Metrics Change:**
- **Desired**: 3
- **Current**: 3
- **Ready**: 2 → 3 (as new pod starts)

**Go to Pods tab:**
- See 3 pods running
- New pod has recent "Age"

**Scale back down:**
1. Repeat steps but change to `1`
2. Watch one pod terminate
3. Metrics show: Desired: 1, Current: 1, Ready: 1

**Key Observation:**
- Deployments can scale dynamically
- Jobs run a fixed number of times (no scaling while running)

---

# Summary: Jobs vs Deployments

## Key Differences

| Feature | Job | Deployment |
|---------|-----|------------|
| **Purpose** | Run once and complete | Run continuously |
| **restartPolicy** | Never | Always |
| **Completion** | Has start and end time | Never completes |
| **Use Cases** | Batch processing, backups, migrations | Web apps, APIs, services |
| **Scaling** | Parallelism (multiple completions) | Replicas (multiple pods running simultaneously) |
| **Self-Healing** | No (once done, stays done) | Yes (recreates pods automatically) |
| **Logs** | Fixed length (one run) | Growing continuously |
| **Pod Status** | Completed | Running |

## When to Use Each

**Use a Job when:**
- Task has a clear beginning and end
- You want it to run once (or N times) then stop
- Examples: data processing, report generation, database migration

**Use a Deployment when:**
- Service should run 24/7
- Need high availability (multiple replicas)
- Examples: web servers, APIs, microservices, message queues

---

# Troubleshooting

## Job Not Completing

**Symptoms:** Job shows "Running" for a long time

**Check:**
1. View logs - is script stuck?
2. Check pod events for errors
3. Verify PVC mounted correctly: `ls /mnt/code-storage` in pod terminal

## Deployment Pods Crashing

**Symptoms:** Pods show "CrashLoopBackOff" or high restart count

**Check:**
1. View logs for Python errors
2. Check if script has syntax errors
3. Verify PVC has the Python scripts

## Can't See Logs

**Symptoms:** "No logs available"

**Solution:**
- Wait a few seconds for pod to start
- Refresh the page
- Check pod is in "Running" or "Completed" status

## PVC Not Binding

**Symptoms:** PVC shows "Pending" status

**Solution:**
- Check storage class exists: `oc get storageclass`
- Verify cluster has available storage
- Check PVC events for error messages

---

# Cleanup

When you're done with the lab:

1. **Delete Deployment:**
   - Navigate to **Workloads → Deployments**
   - Click three dots (⋮) next to `web-service`
   - Click **"Delete Deployment"**

2. **Delete Job:**
   - Navigate to **Workloads → Jobs**
   - Click three dots (⋮) next to `data-processing-job`
   - Click **"Delete Job"**

3. **Delete PVC:**
   - Navigate to **Storage → PersistentVolumeClaims**
   - Click three dots (⋮) next to `code-storage`
   - Click **"Delete PersistentVolumeClaim"**

**Note:** Deleting the PVC will delete all data stored in it (including the Python scripts).

---

# Next Steps

After completing this lab, you understand:
- ✅ How to store code in OpenShift persistent storage
- ✅ Difference between Jobs and Deployments
- ✅ How to create and manage workloads via UI
- ✅ How to view logs and monitor metrics
- ✅ Self-healing and scaling capabilities

**Explore More:**
- Try creating a CronJob (scheduled Jobs)
- Add a Service to expose the Deployment
- Experiment with different resource limits
- Try mounting ConfigMaps instead of PVCs
