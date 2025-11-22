# OpenShift Basics Lab Guide

**Duration**: 30 minutes
**Format**: Self-paced, hands-on
**Interface**: OpenShift Web Console

---

## Before You Start

### Prerequisites

1. **OpenShift Console Access**
   - Console URL: `https://console-openshift-console.apps.[YOUR-CLUSTER-DOMAIN]`
   - Username and password provided by your platform team

2. **Project/Namespace**
   - You need a project (namespace) to deploy resources
   - Ask platform team if you don't have one

3. **Update YAML Files**
   - Replace `namespace: parabricks-test` with YOUR project name in:
     - `job-example.yaml`
     - `deployment-example.yaml`

---

## Part 1: Deploy a Job (10 minutes)

### What is a Job?

**Job** = Runs a task **once** and then stops

**Use Cases**:
- Data processing pipelines
- Report generation
- Database migrations
- Batch analytics
- ML model training

---

### Option A: Developer Perspective

#### Step 1: Login and Switch Perspective

1. Open browser → Navigate to OpenShift Console
2. Login with your credentials
3. **Top-left corner**: Click dropdown (shows "Administrator" or "Developer")
4. Select **"Developer"**

#### Step 2: Select Project

1. **Top navigation bar**: Click **"Project:"** dropdown
2. Select your assigned project

#### Step 3: Import Job YAML

1. **Left sidebar**: Click **"+Add"**
2. Click tile: **"Import YAML"**
3. Copy contents of `job-example.yaml`
4. Paste into the YAML editor
5. **Verify** namespace matches your project
6. Click **"Create"** button

#### Step 4: Watch Job Execute

1. **Left sidebar**: Click **"Topology"**
2. You'll see a circle labeled **"data-processing-job"**
3. Watch status change:
   - **Pending** (creating pod)
   - **Running** (executing task)
   - **Completed** (finished) ← Takes ~20 seconds

#### Step 5: View Job Logs

1. Click on the **"data-processing-job"** circle
2. Right panel opens → Click **"Resources"** tab
3. Click on pod name: `data-processing-job-xxxxx`
4. Click **"Logs"** tab
5. **You'll see**:
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

#### Step 6: Check Events

1. Still in pod view → Click **"Events"** tab
2. You'll see timeline:
   ```
   Pulling image registry.access.redhat.com/ubi8/ubi-minimal:latest...
   Successfully pulled image...
   Created container processor
   Started container processor
   ```

---

### Option B: Administrator Perspective

#### Step 1: Login

1. Open OpenShift Console
2. Login with credentials
3. Should be in **Administrator** perspective (default)

#### Step 2: Navigate to Jobs

1. **Left sidebar**: Click **"Workloads"** to expand
2. Click **"Jobs"**

#### Step 3: Create Job

1. **Top of page**: Click **"Create Job"** button
2. YAML editor appears
3. **Delete** any default YAML
4. Copy and paste contents of `job-example.yaml`
5. **Verify** namespace matches your project
6. Click **"Create"**

#### Step 4: View Job

1. You'll see **"data-processing-job"** in the Jobs list
2. Wait ~20 seconds
3. **Status** column changes: Running → Complete
4. **Completions** column shows: 1/1

#### Step 5: View Logs

1. Click on **"data-processing-job"** (name is a link)
2. Scroll down to **"Pods"** section
3. Click on pod name: `data-processing-job-xxxxx`
4. Click **"Logs"** tab
5. See complete job output

#### Step 6: View Events

1. In pod details, click **"Events"** tab
2. Review the timeline of actions

---

### Key Observations - Jobs

✅ **Pod Status**: "Completed" (not "Running")
✅ **Restart Count**: 0 (doesn't restart)
✅ **Logs**: Fixed output (task complete)
✅ **Duration**: ~20 seconds then stops

---

## Part 2: Deploy a Deployment (10 minutes)

### What is a Deployment?

**Deployment** = Keeps service **always running**

**Use Cases**:
- REST APIs
- Web applications
- Microservices
- Databases
- Message queues

---

### Option A: Developer Perspective

#### Step 1: Import Deployment YAML

1. Click **"+Add"** (left sidebar)
2. Click **"Import YAML"**
3. Copy contents of `deployment-example.yaml`
4. Paste into editor
5. **Verify** namespace is correct
6. Click **"Create"**

#### Step 2: View in Topology

1. Go to **"Topology"**
2. You'll see: **"web-service"** with blue circle showing **"2"**
   - This means 2 pods (replicas) are running

#### Step 3: View Deployment Logs

1. Click on **"web-service"** circle
2. Right panel → **"Resources"** tab
3. You'll see 2 pods listed:
   - `web-service-xxxxx-yyyyy`
   - `web-service-xxxxx-zzzzz`
4. Click on first pod
5. Click **"Logs"** tab
6. **You'll see streaming output**:
   ```
   ==========================================
   DEPLOYMENT: Web Service Started
   ==========================================
   Pod: web-service-xxxxx-yyyyy

   Service is running and ready to handle requests...

   [timestamp] Heartbeat - Pod web-service-xxxxx-yyyyy is healthy
   [timestamp] Active connections: 23
   [timestamp] Memory usage: 42%
   [timestamp] CPU usage: 35%
   ---
   [timestamp] Heartbeat - Pod web-service-xxxxx-yyyyy is healthy
   ...
   ```
7. **Notice**: Logs keep streaming (pod is still running)

#### Step 4: Test Self-Healing

1. While viewing a pod, click **"Actions"** dropdown (top-right)
2. Select **"Delete Pod"**
3. Click **"Delete"** to confirm
4. Go back to **Topology** view
5. **Watch what happens**:
   - Old pod shows **"Terminating"**
   - **New pod automatically created!**
   - After ~5 seconds, new pod is **"Running"**
6. **This is self-healing in action!**

#### Step 5: Scale the Deployment

1. In Topology, click **"web-service"** circle
2. Right panel → **"Details"** tab
3. Find section showing: **"Pod: 2"**
4. Click **up arrow** (↑)
5. **Watch**: 3rd pod created
6. Click **down arrow** (↓) twice
7. **Watch**: Pods terminate until only 1 remains

---

### Option B: Administrator Perspective

#### Step 1: Navigate to Deployments

1. **Left sidebar**: **Workloads** → **Deployments**

#### Step 2: Create Deployment

1. Click **"Create Deployment"** button
2. **Delete** default YAML
3. Paste contents of `deployment-example.yaml`
4. **Verify** namespace
5. Click **"Create"**

#### Step 3: View Deployment

1. You'll see **"web-service"** in Deployments list
2. **Status** column shows: **2/2 pods**
3. Click on **"web-service"** (name is link)

#### Step 4: View Pods

1. Scroll to **"Pods"** section
2. You'll see 2 pods listed, both **"Running"**
3. Click on a pod name
4. Click **"Logs"** tab
5. See streaming heartbeat messages

#### Step 5: Test Self-Healing

1. In pod view, **"Actions"** → **"Delete Pod"**
2. Confirm deletion
3. Go back to Deployment details
4. **"Pods"** section: Watch new pod appear

#### Step 6: Scale

1. In Deployment details, click **"Actions"** → **"Edit Pod Count"**
2. Change from `2` to `3`
3. Click **"Save"**
4. Watch 3rd pod created
5. Repeat to scale down to `1`

---

### Key Observations - Deployments

✅ **Pod Status**: "Running" (continuously)
✅ **Self-Healing**: Deleted pods automatically replaced
✅ **Logs**: Streaming (ongoing output)
✅ **Scaling**: Easy to increase/decrease replicas

---

## Part 3: Monitoring & Debugging (10 minutes)

### View Metrics

#### For a Pod:

1. **Workloads** → **Pods** → Click any running pod
2. Click **"Metrics"** tab
3. You'll see graphs:
   - **CPU Usage** (over time)
   - **Memory Usage** (over time)
   - **Filesystem Usage**
   - **Network I/O**

**Note**: Metrics may take 1-2 minutes to populate

#### For a Deployment:

1. **Workloads** → **Deployments** → Click **"web-service"**
2. Look for **"Metrics"** or **"Observe"** tab
3. See aggregated metrics for all pods

---

### View Events

#### Project-Wide Events:

1. **Left sidebar**:
   - Developer: **"Project"** → **"Events"**
   - Administrator: **"Home"** → **"Events"**
2. You'll see chronological list:
   ```
   [Timestamp] Pod created: data-processing-job-xxxxx
   [Timestamp] Container started: data-processing-job-xxxxx
   [Timestamp] Pod created: web-service-xxxxx-yyyyy
   [Timestamp] Pod scheduled: web-service-xxxxx-zzzzz
   ```

#### Filter Events:

1. Use search box at top
2. Type: `web-service` → Shows only web-service events
3. Filter by type: Normal, Warning, Error

---

### Understanding Resource Usage

#### View Resource Limits:

1. Click on any pod
2. **"Details"** tab → Scroll to **"Containers"** section
3. See:
   ```
   Resources:
     Requests: 100m CPU, 128Mi memory
     Limits: 200m CPU, 256Mi memory
   ```

**What this means**:
- **Requests**: Minimum resources guaranteed
- **Limits**: Maximum resources allowed
- Pod won't be scheduled if requests can't be met
- Pod killed if it exceeds limits

---

## Comparison: Job vs Deployment

### Side-by-Side

| Aspect | Job | Deployment |
|--------|-----|------------|
| **Purpose** | Run task once | Always running service |
| **Completion** | Stops when done | Runs indefinitely |
| **Pod Status** | Completed | Running |
| **Restart Policy** | Never | Always (auto-restart) |
| **Self-Healing** | No | Yes |
| **Scaling** | N/A | Yes (replicas) |
| **Logs** | Static (completed) | Streaming (live) |
| **Use Cases** | Batch jobs, migrations | APIs, web apps, services |

---

## Hands-On Exercise

### Challenge 1: Modify the Job

1. Edit `job-example.yaml`
2. Change `sleep 3` to `sleep 1` (faster processing)
3. Delete old Job: **Actions** → **Delete Job**
4. Create updated Job
5. Verify it completes faster

### Challenge 2: Scale Practice

1. Scale **web-service** to 5 replicas
2. View logs from different pods (different hostnames)
3. Delete 2 pods simultaneously
4. Watch both get replaced
5. Scale back to 2

### Challenge 3: Intentional Failure

1. Edit `deployment-example.yaml`
2. Change image to: `registry.access.redhat.com/ubi8/does-not-exist:latest`
3. Create Deployment
4. Watch pod fail with **ImagePullBackOff**
5. Check **Events** tab for error details
6. Fix image name and recreate

---

## Troubleshooting Guide

### Pod Won't Start

**Symptom**: Pod stuck in **Pending** or **ContainerCreating**

**Check**:
1. **Events** tab → Look for errors
2. Common causes:
   - **Image pull error**: Wrong image name or no access
   - **Insufficient resources**: Cluster doesn't have capacity
   - **Pending PVC**: Waiting for storage (not applicable here)

**Fix**:
- Image issues: Verify image name, check registry access
- Resources: Reduce requests or ask platform team for quota increase

---

### Pod Keeps Crashing

**Symptom**: Pod shows **CrashLoopBackOff** or high restart count

**Check**:
1. **Logs** tab → Look for application errors
2. **Events** tab → See crash reason

**Fix**:
- Application error: Fix code/configuration
- OOMKilled: Increase memory limits
- Liveness probe failing: Adjust probe settings

---

### Can't Create Resources

**Symptom**: "Forbidden" or permission errors

**Fix**:
1. Verify you're in correct project
2. Check with platform team about RBAC permissions
3. You need `edit` or `admin` role in the project

---

### Images Won't Pull

**Symptom**: **ImagePullBackOff** error

**Check**:
1. Is image name correct?
2. Does cluster have internet access?
3. Does cluster use internal mirror?

**Fix**:
- Ask platform team for:
  - Internal registry URL
  - Mirrored image locations
  - Image pull secrets (if needed)

---

## Next Steps

After completing this lab:

### 1. Explore Services

**Goal**: Expose your Deployment internally

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-service-svc
spec:
  selector:
    app: demo
    type: deployment
  ports:
  - port: 8080
    targetPort: 8080
```

### 2. Try Routes

**Goal**: Make your app accessible from outside

Developer → **+Add** → **Create Route**
- Select your Service
- Get external URL

### 3. Use ConfigMaps

**Goal**: Externalize configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  environment: production
  log_level: info
```

Reference in Deployment:
```yaml
env:
- name: ENVIRONMENT
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: environment
```

### 4. Add Secrets

**Goal**: Store sensitive data securely

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
stringData:
  username: admin
  password: super-secret
```

### 5. Set Resource Limits

**Goal**: Control resource usage

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### 6. Health Checks

**Goal**: Automatic health monitoring

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

---

## Additional Resources

### Official Documentation

- **OpenShift Docs**: https://docs.openshift.com/
- **Kubernetes Concepts**: https://kubernetes.io/docs/concepts/
- **YAML Reference**: https://kubernetes.io/docs/reference/

### Internal Resources

- **Platform Team**: [INSERT CONTACT]
- **Slack Channel**: [INSERT CHANNEL]
- **Wiki/Confluence**: [INSERT LINK]
- **Support Portal**: [INSERT LINK]

### Video Tutorials

- [INSERT INTERNAL VIDEOS IF AVAILABLE]

---

## Cleanup

When finished with the lab:

### Developer Perspective:

1. **Topology** → Click resource → **Actions** → **Delete**
2. Repeat for both Job and Deployment

### Administrator Perspective:

1. **Workloads** → **Jobs** → Three dots (⋮) → **Delete Job**
2. **Workloads** → **Deployments** → Three dots (⋮) → **Delete Deployment**

### Verify Cleanup:

```
Workloads → Pods → Should show no pods (or only system pods)
```

---

## Feedback

Help us improve this lab!

**What worked well?**
**What was confusing?**
**What should we add?**

Send feedback to: [INSERT FEEDBACK EMAIL/FORM]

---

**Congratulations!** You've completed the OpenShift Basics Lab. You now understand Jobs vs Deployments and how to deploy, monitor, and troubleshoot workloads in OpenShift.

Happy coding! 🚀
