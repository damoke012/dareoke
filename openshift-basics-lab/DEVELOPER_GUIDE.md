# OpenShift Jobs vs Deployments - Developer Guide

## For Developers with No Platform Knowledge

This guide explains how to run your code in OpenShift, understand metrics, and view logs.

---

## 🎯 Quick Start: The Big Picture

Think of OpenShift like a computer in the cloud that runs your code:

- **Job** = Run a script once (like double-clicking a .py file)
- **Deployment** = Keep a program running 24/7 (like a web server)
- **ConfigMap** = Cloud storage for your code files (like S3 or Google Drive)

---

## 📦 What We're Building

### Scenario
You have Python scripts stored in cloud storage (S3/Azure Blob/etc.), and you want to:
1. Run a data processing script once (Job)
2. Keep a web service running continuously (Deployment)

### Files Structure
```
openshift-basics-lab/
├── configmap-scripts.yaml       ← Your code storage (like S3 bucket)
├── job-with-storage.yaml         ← Run once task
├── deployment-with-storage.yaml  ← Always-running service
└── DEVELOPER_GUIDE.md           ← You are here
```

---

## 🚀 Step-by-Step Tutorial

### Step 1: Upload Your Code to "Cloud Storage"

In real life, you'd upload code to S3. In OpenShift, we use a **ConfigMap**.

```bash
# Create the ConfigMap (uploads your code)
oc apply -f configmap-scripts.yaml
```

**What just happened?**
- Created a "virtual drive" called `demo-scripts`
- Stored two Python files: `process_data.py` and `web_server.py`
- Pods can now "mount" this drive to access the code

**Verify it worked:**
```bash
oc get configmap demo-scripts
oc describe configmap demo-scripts
```

---

### Step 2A: Run a Job (One-Time Task)

**Use Case:** Process data, generate a report, run a backup

```bash
# Create the Job
oc apply -f job-with-storage.yaml

# Watch it run
oc get jobs
oc get pods
```

**What's happening?**
1. OpenShift creates a pod
2. Mounts the `demo-scripts` ConfigMap as `/scripts`
3. Runs: `python3 /scripts/process_data.py`
4. Script completes
5. Pod stays around (so you can check logs)
6. Job status = "Complete"

**View the output:**
```bash
# See the logs
oc logs job/data-processing-job

# You should see:
# ============================================================
# DATA PROCESSING JOB
# ============================================================
# Start Time: 2025-11-17 13:00:00
# ...
# JOB COMPLETED SUCCESSFULLY
```

**Check metrics:**
```bash
# How long did it take?
oc describe job data-processing-job

# Look for:
# - Start Time
# - Completion Time
# - Duration: ~10 seconds
# - Succeeded: 1
```

---

### Step 2B: Run a Deployment (Always-Running Service)

**Use Case:** Web server, API, microservice

```bash
# Create the Deployment
oc apply -f deployment-with-storage.yaml

# Watch it start
oc get deployments
oc get pods
```

**What's happening?**
1. OpenShift creates 2 pods (replicas: 2)
2. Each pod mounts the `demo-scripts` ConfigMap
3. Each runs: `python3 /scripts/web_server.py`
4. Pods keep running forever (like a web server)
5. If a pod crashes, OpenShift auto-creates a new one

**View the output:**
```bash
# See logs from all pods
oc logs deployment/web-service --all-containers=true

# Or view specific pod
oc get pods  # Get pod names
oc logs web-service-xxxxx-yyyyy

# You should see repeating heartbeats:
# [2025-11-17 13:00:00] Heartbeat - Pod web-service-xxxxx is healthy
# [2025-11-17 13:00:00] Active connections: 42
# [2025-11-17 13:00:00] Memory usage: 55%
```

---

## 📊 Understanding Metrics

### Job Metrics

```bash
oc describe job data-processing-job
```

**Key Metrics:**
```
Start Time:      Sun, 17 Nov 2025 13:00:00 +0000
Completion Time: Sun, 17 Nov 2025 13:00:10 +0000
Duration:        10s
Parallelism:     1
Completions:     1
Succeeded:       1
Failed:          0
```

**What it means:**
- **Duration**: How long the job took
- **Succeeded**: How many times it completed successfully
- **Failed**: How many times it failed (then retried)
- **Parallelism**: How many pods run at once

---

### Deployment Metrics

```bash
oc describe deployment web-service
```

**Key Metrics:**
```
Replicas:               2 desired | 2 updated | 2 total | 2 available
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
```

**What it means:**
- **Desired**: How many pods you want
- **Available**: How many pods are healthy and ready
- **Conditions**: Overall health status

**Pod-level metrics:**
```bash
oc get pods

NAME                          READY   STATUS    RESTARTS   AGE
web-service-6d7f8c9b-abcde    1/1     Running   0          5m
web-service-6d7f8c9b-fghij    1/1     Running   0          5m
```

**What it means:**
- **READY (1/1)**: 1 out of 1 containers in the pod is ready
- **STATUS**: Current state (Running, Pending, Error, etc.)
- **RESTARTS**: How many times the container crashed and restarted
- **AGE**: How long the pod has been running

---

## 📝 Viewing Logs

### Job Logs

```bash
# Method 1: By job name
oc logs job/data-processing-job

# Method 2: By pod name
oc get pods  # Find the job pod
oc logs data-processing-job-xxxxx

# Follow logs in real-time (while job runs)
oc logs -f job/data-processing-job
```

---

### Deployment Logs

```bash
# All pods at once
oc logs deployment/web-service --all-containers=true

# Specific pod
oc logs web-service-xxxxx-yyyyy

# Follow logs in real-time
oc logs -f deployment/web-service

# Last 20 lines only
oc logs deployment/web-service --tail=20

# Logs from last hour
oc logs deployment/web-service --since=1h
```

---

## 🔍 Key Differences: Job vs Deployment

| Feature | Job | Deployment |
|---------|-----|------------|
| **Purpose** | Run once and complete | Run continuously |
| **Completion** | Shows "Complete" when done | Never completes |
| **Pod Behavior** | Dies when script finishes | Runs forever |
| **Restart Policy** | Never | Always (auto-restart on crash) |
| **Use Cases** | Batch jobs, data processing, backups | Web servers, APIs, services |
| **Replicas** | Usually 1 | Usually 2+ (high availability) |
| **Self-Healing** | No (runs once) | Yes (auto-restart) |
| **Metrics Focus** | Duration, success/failure | Uptime, availability |

---

## 🧪 Hands-On Experiments

### Experiment 1: Test Job Completion

```bash
# Run the job
oc apply -f job-with-storage.yaml

# Watch status change from Running → Complete
oc get jobs -w

# After ~10 seconds, press Ctrl+C and check
oc get jobs
# STATUS should show: Complete

# Try to run again - creates a new job pod
oc delete job data-processing-job
oc apply -f job-with-storage.yaml
```

---

### Experiment 2: Test Deployment Self-Healing

```bash
# Start deployment
oc apply -f deployment-with-storage.yaml

# Get pod names
oc get pods

# Delete one pod (simulate crash)
oc delete pod web-service-xxxxx-yyyyy

# Watch OpenShift auto-create a replacement
oc get pods -w

# You'll see:
# 1. Old pod: Terminating
# 2. New pod: ContainerCreating → Running
```

---

### Experiment 3: Scale Deployment

```bash
# Start with 2 pods
oc get pods

# Scale up to 5 pods
oc scale deployment web-service --replicas=5

# Watch new pods start
oc get pods -w

# Scale down to 1 pod
oc scale deployment web-service --replicas=1

# Watch pods terminate
oc get pods -w
```

---

### Experiment 4: Modify the Code

```bash
# Edit the ConfigMap
oc edit configmap demo-scripts

# Change something in the Python code
# Save and exit

# For Job: Delete and recreate
oc delete job data-processing-job
oc apply -f job-with-storage.yaml

# For Deployment: Restart pods to pick up new code
oc rollout restart deployment web-service

# Watch pods restart with new code
oc get pods -w
```

---

## 🎓 Understanding the YAML Files

### ConfigMap Structure

```yaml
apiVersion: v1
kind: ConfigMap          # Type: Storage for config/code
metadata:
  name: demo-scripts     # Name: How you reference it
data:
  process_data.py: |     # File name
    #!/usr/bin/env python3
    # ... your Python code ...
```

**Think of it as:** A folder with files stored in OpenShift

---

### Job Structure

```yaml
apiVersion: batch/v1
kind: Job                # Type: Run-once task
metadata:
  name: data-processing-job
spec:
  template:
    spec:
      restartPolicy: Never    # Don't restart when done
      volumes:
      - name: scripts
        configMap:
          name: demo-scripts  # Mount this ConfigMap
      containers:
      - name: processor
        command: ["python3"]
        args: ["/scripts/process_data.py"]  # Run this file
        volumeMounts:
        - name: scripts
          mountPath: /scripts   # Mount at this path
```

**Flow:**
1. Mount ConfigMap as `/scripts` folder
2. Run `python3 /scripts/process_data.py`
3. Exit when script completes
4. Don't restart

---

### Deployment Structure

```yaml
apiVersion: apps/v1
kind: Deployment         # Type: Always-running service
spec:
  replicas: 2            # Run 2 copies
  template:
    spec:
      volumes:
      - name: scripts
        configMap:
          name: demo-scripts
      containers:
      - name: web
        command: ["python3"]
        args: ["/scripts/web_server.py"]
        volumeMounts:
        - name: scripts
          mountPath: /scripts
        livenessProbe:   # Health check
          exec:
            command: ["echo", "healthy"]
```

**Flow:**
1. Mount ConfigMap as `/scripts` folder
2. Start 2 pods
3. Each runs `python3 /scripts/web_server.py`
4. Keep running forever
5. If pod crashes, restart it
6. Check health every 10 seconds

---

## 🛠️ Common Tasks

### View Resource Usage

```bash
# CPU and Memory usage
oc adm top pods

# Output:
# NAME                      CPU(cores)   MEMORY(bytes)
# web-service-xxx-yyy       1m           45Mi
```

---

### View Events (Troubleshooting)

```bash
# See what OpenShift is doing
oc get events --sort-by='.lastTimestamp'

# Common events:
# - Pulling image
# - Created container
# - Started container
# - Killing container
# - Failed to pull image (error)
```

---

### Cleanup

```bash
# Delete everything
oc delete job data-processing-job
oc delete deployment web-service
oc delete configmap demo-scripts

# Verify deletion
oc get jobs
oc get deployments
oc get configmaps
```

---

## ❓ FAQ for Developers

### Q: How do I know if my Job succeeded?
```bash
oc get jobs
# Look for "COMPLETIONS" column: 1/1 = success
```

### Q: Why does my Deployment never show "Complete"?
Because deployments run forever! They only complete if you delete them.

### Q: How do I update my code?
1. Edit the ConfigMap: `oc edit configmap demo-scripts`
2. For Job: Delete and recreate
3. For Deployment: Restart: `oc rollout restart deployment web-service`

### Q: Why do I have 2 pods for one Deployment?
**High availability!** If one pod crashes, the other keeps running. No downtime.

### Q: What if my Job fails?
Check logs: `oc logs job/data-processing-job`
Look for Python errors, then fix your code.

### Q: Can I run my existing Python script?
**Yes!** Just:
1. Add it to the ConfigMap
2. Update the `args:` line to point to your script
3. Add any pip packages to the container if needed

---

## 📚 Cheat Sheet

```bash
# Create
oc apply -f <file>.yaml

# View
oc get jobs
oc get deployments
oc get pods
oc get configmaps

# Logs
oc logs job/<name>
oc logs deployment/<name>
oc logs <pod-name>

# Details
oc describe job/<name>
oc describe deployment/<name>
oc describe pod/<name>

# Delete
oc delete job/<name>
oc delete deployment/<name>
oc delete configmap/<name>

# Scale
oc scale deployment/<name> --replicas=<number>

# Restart
oc rollout restart deployment/<name>
```

---

## 🎉 Summary

**Job:**
- Runs your script once
- Like running `python script.py` on your laptop
- Use for: batch processing, reports, migrations

**Deployment:**
- Keeps your script running 24/7
- Like a web server that never stops
- Use for: APIs, web apps, services

**ConfigMap:**
- Stores your code files
- Like S3 or cloud storage
- Pods mount it to access code

**Metrics:**
- Jobs: Duration, success/failure
- Deployments: Uptime, pod health, restarts

**Logs:**
- `oc logs` shows your script's print statements
- Check logs to debug issues

---

## 🚀 Next Steps

1. Try the experiments above
2. Modify the Python scripts in the ConfigMap
3. Create your own Job for your use case
4. Create your own Deployment for a service
5. Learn about Services (networking) and Routes (external access)

**Need Help?**
- Check logs: `oc logs <pod-name>`
- Check events: `oc get events`
- Describe resource: `oc describe <type>/<name>`

Happy coding! 🎊
