# OpenShift Basics Lab - UI Guide for Developers

**Duration**: 30 minutes
**Audience**: Developers new to OpenShift
**Prerequisites**: Access to OpenShift Console

---

## Lab Overview

Learn the difference between **Jobs** (run once) and **Deployments** (always running) using the OpenShift web console.

**What You'll Learn**:
1. Deploy a Job (batch processing)
2. Deploy a Deployment (service)
3. View logs and monitor pods
4. Understand when to use each

---

## Part 1: Understanding Jobs (10 minutes)

### What is a Job?

**Job** = Runs a task **once** and completes

**Use Cases**:
- Data processing
- Batch analytics
- Report generation
- Model training
- Database migrations

### Deploy a Job via UI

1. **Login to OpenShift Console**
   - URL: `https://console-openshift-console.apps.[your-cluster]`
   - Login with your credentials

2. **Switch to Developer Perspective**
   - Top left corner: Click dropdown
   - Select **"Developer"**

3. **Select Your Project**
   - Top bar: Project dropdown
   - Select: `parabricks-test` (or your project)

4. **Import YAML**
   - Click **"+Add"** (left sidebar)
   - Click **"Import YAML"**
   - Copy contents of `job-example.yaml`
   - Paste into editor
   - Click **"Create"**

5. **Watch Job Execute**
   - Go to **"Topology"** (left sidebar)
   - You'll see: **"data-processing-job"** with icon
   - Status shows: **Running** → then **Completed**

6. **View Job Logs**
   - Click on the Job circle in Topology
   - Right panel opens
   - Click **"Resources"** tab
   - Click on the Pod name (e.g., `data-processing-job-xxxxx`)
   - Click **"Logs"** tab
   - You'll see:
     ```
     ==========================================
     JOB: Data Processing Task
     ==========================================

     Start Time: [timestamp]

     Step 1: Loading data...
     ✓ Data loaded (1000 records)

     Step 2: Processing records...
       Processing batch 1/5...
       Processing batch 2/5...
       ...
     ✓ All records processed

     JOB COMPLETED SUCCESSFULLY
     ==========================================
     ```

7. **View Events**
   - Still in Pod details
   - Click **"Events"** tab
   - You'll see:
     ```
     Pulling image...
     Successfully pulled image...
     Created container...
     Started container...
     ```

8. **Check Job Status**
   - Go back to Topology
   - Green checkmark = Success
   - Job pod shows: **Completed**
   - **Key Point**: Pod is stopped, won't restart

---

## Part 2: Understanding Deployments (10 minutes)

### What is a Deployment?

**Deployment** = Keeps pods **always running**

**Use Cases**:
- Web APIs
- Microservices
- Databases
- Message queues
- Always-on services

### Deploy a Deployment via UI

1. **Import YAML**
   - Click **"+Add"**
   - Click **"Import YAML"**
   - Copy contents of `deployment-example.yaml`
   - Paste into editor
   - Click **"Create"**

2. **Watch Deployment**
   - Go to **"Topology"**
   - You'll see: **"web-service"** with blue circle
   - Shows: **"2 of 2 pods"** (2 replicas running)

3. **View Deployment Logs**
   - Click on **"web-service"** circle
   - Right panel: Click **"Resources"** tab
   - You'll see 2 pods listed
   - Click on first pod: `web-service-xxxxx-yyyyy`
   - Click **"Logs"** tab
   - You'll see continuous output:
     ```
     ==========================================
     DEPLOYMENT: Web Service Started
     ==========================================
     Pod: web-service-xxxxx-yyyyy

     Service is running and ready to handle requests...

     [timestamp] Heartbeat - Pod web-service-xxxxx-yyyyy is healthy
     [timestamp] Active connections: 25
     [timestamp] Memory usage: 45%
     [timestamp] CPU usage: 38%
     ---
     [timestamp] Heartbeat - Pod web-service-xxxxx-yyyyy is healthy
     [timestamp] Active connections: 32
     ...
     ```
   - **Key Point**: Logs keep streaming (pod keeps running)

4. **Test Self-Healing**
   - In Topology, click **"web-service"**
   - Right panel: **"Resources"** tab
   - Click on one pod name
   - Click **"Actions"** dropdown (top right)
   - Select **"Delete Pod"**
   - Confirm deletion
   - **Watch what happens**:
     - Pod shows **"Terminating"**
     - New pod automatically created
     - New pod shows **"Running"**
     - **Always maintains 2 pods!**

5. **Scale the Deployment**
   - In Topology, click **"web-service"** circle
   - Right panel: Click **"Details"** tab
   - Find **"Pod"** section showing: `2 of 2 pods`
   - Click **up arrow** to increase to 3
   - Watch: 3rd pod created automatically
   - Click **down arrow** to decrease to 1
   - Watch: Pods terminate to maintain 1

---

## Part 3: Monitoring & Debugging (10 minutes)

### View Metrics

1. **Pod Metrics**
   - Click on any running pod
   - Click **"Metrics"** tab
   - You'll see graphs:
     - **Memory Usage** (over time)
     - **CPU Usage** (over time)
     - **Filesystem Usage**
     - **Network Receive/Transmit**

2. **Deployment Metrics**
   - Go to Topology
   - Click **"web-service"**
   - Click **"Observe"** tab
   - View:
     - Pod count over time
     - Resource usage aggregated
     - Request rates (if exposed)

### View Events

1. **Project Events**
   - Left sidebar: Click **"Project"**
   - Click **"Events"** tab
   - See all events in chronological order:
     ```
     Pod created: data-processing-job-xxxxx
     Container started: data-processing-job-xxxxx
     Pod created: web-service-xxxxx-yyyyy
     Pod scheduled: web-service-xxxxx-zzzzz
     ```

2. **Filter Events**
   - Use filter at top: Type "web-service"
   - Shows only web-service events
   - Change filter to "Failed" to see errors

### Check Resource Usage

1. **Project Quota**
   - Left sidebar: Click **"Project"**
   - Click **"Details"** tab
   - See:
     - CPU usage: X cores / Y cores
     - Memory usage: X GB / Y GB
     - Pods: X / Y

2. **Pod Resource Limits**
   - Click on a pod
   - Click **"Details"** tab
   - Scroll to **"Containers"** section
   - See:
     ```
     Resources:
       Requests: 100m CPU, 128Mi memory
       Limits: 200m CPU, 256Mi memory
     ```

---

## Key Differences: Job vs Deployment

| Aspect | Job | Deployment |
|--------|-----|------------|
| **Purpose** | Run task once | Keep service running |
| **Completion** | Finishes and stops | Runs indefinitely |
| **Restart** | No automatic restart | Auto-restarts if crash |
| **Replicas** | Usually 1 | Can scale (1, 2, 3...) |
| **Use Case** | Batch processing | Web services, APIs |
| **Logs** | Fixed (task output) | Continuous streaming |
| **Self-Healing** | No | Yes (recreates pods) |

---

## Hands-On Exercise

**Challenge**: Create your own Job and Deployment

### Exercise 1: Modify the Job

1. Go to Topology → Click "data-processing-job"
2. Click **"Actions"** → **"Edit Job"**
3. Find the `sleep 3` lines
4. Change to `sleep 1` (faster)
5. Click **"Save"**
6. Delete old job: **"Actions"** → **"Delete Job"**
7. Re-apply the YAML with your changes
8. Watch it complete faster!

### Exercise 2: Scale the Deployment

1. Scale web-service to 5 replicas
2. Watch pods created
3. View logs from each pod (different hostnames)
4. Delete one pod
5. Watch automatic replacement

---

## Troubleshooting via UI

### Pod Won't Start

1. **Check Pod Status**
   - Click pod in Topology
   - Look at status: Pending, ContainerCreating, CrashLoopBackOff

2. **Check Events**
   - Click **"Events"** tab
   - Look for errors:
     - "Image pull error" = Bad image name
     - "Insufficient memory" = Not enough resources
     - "InvalidImageName" = Typo in image URL

3. **Check Logs**
   - If pod started but failed
   - Click **"Logs"** tab
   - Look for error messages in output

### Pod Keeps Restarting

1. **Check Restart Count**
   - Pod details → **"Details"** tab
   - Look at "Restart Count"
   - High number = crashing repeatedly

2. **Check Container Logs**
   - **"Logs"** tab
   - Look at the end for crash reason

3. **Check Liveness/Readiness Probes**
   - **"Details"** tab → Scroll to Probes
   - Failing probes = pod killed/not ready

---

## Monitoring Best Practices

### What to Watch

1. **Pod Status**
   - Green = Running
   - Blue ring = Pending
   - Red = Failed
   - Yellow = Warning

2. **Resource Usage**
   - CPU near limit = need more CPU
   - Memory near limit = risk of OOM kill
   - Check Metrics tab regularly

3. **Events**
   - Review every 5-10 minutes
   - Look for warnings (yellow)
   - Address errors (red) immediately

4. **Logs**
   - Check for application errors
   - Look for patterns (repeated errors)
   - Use search to filter

---

## Quick Reference

### Navigate UI

| Where | How |
|-------|-----|
| **Import YAML** | "+Add" → "Import YAML" |
| **View Topology** | Left sidebar → "Topology" |
| **View Logs** | Click pod → "Logs" tab |
| **View Events** | Click resource → "Events" tab |
| **View Metrics** | Click pod → "Metrics" tab |
| **Delete Resource** | Click resource → "Actions" → "Delete" |
| **Scale Deployment** | Click deployment → Details → Pod count arrows |

### Common Actions

```
Create:     "+Add" → "Import YAML" → Paste → Create
View Logs:  Topology → Click pod → Logs tab
Scale:      Topology → Click deployment → Details → Arrows
Delete:     Topology → Click resource → Actions → Delete
Edit:       Topology → Click resource → Actions → Edit
```

---

## Summary

**What You Learned**:

✅ **Job**: Runs once, completes, stops
- Used for: Batch processing, one-time tasks
- Example: Data processing job

✅ **Deployment**: Always running, self-healing
- Used for: Services, APIs, databases
- Example: Web service with 2 replicas

✅ **Monitoring**: Logs, Events, Metrics
- Logs: See application output
- Events: See Kubernetes actions
- Metrics: See resource usage

✅ **UI Skills**:
- Import YAML
- View Topology
- Check pod status
- Scale deployments
- Debug with logs/events

---

## Next Steps

1. **Try with your own container image**
2. **Add environment variables** to YAML
3. **Experiment with resource limits**
4. **Create a Service** to expose the Deployment
5. **Set up monitoring alerts**

---

**Questions?** Review the OpenShift documentation or ask your platform team!
