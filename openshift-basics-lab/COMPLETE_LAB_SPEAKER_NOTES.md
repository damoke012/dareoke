# OpenShift Basics Lab - Complete Speaker Notes (UI Only)
Total Time: 25-30 minutes
Format: OpenShift Web Console demo with hands-on labs

## Setup Before Demo
- Open OpenShift Web Console
- Select project/namespace

---

## PART 1: Storage Setup (3 minutes)

### Create PVC
"First, let's set up persistent storage. We need a PVC to store data that survives pod restarts."

Steps:
1. Left sidebar → Project → Project details
2. Go Storage → Click PersistentVolumeClaims tab
3. Click Create PersistentVolumeClaim
4. Paste YAML:

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: code-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi

5. Click Create

Key YAML Notes:
- kind: PersistentVolumeClaim - Requests storage from the cluster
- accessModes: ReadWriteOnce - Can be mounted read-write by one node (alternatives: ReadWriteMany, ReadOnlyMany)
- storage: 1Gi - Size of storage requested; cluster provisions from available StorageClass

This creates a 1GB persistent volume. Notice the status changes to Bound.

---

## PART 2: Upload Data via Helper Pod (4 minutes)

### Deploy Upload Helper Pod
To upload files to our PVC, we'll create a helper pod with the volume mounted.

Steps:
1. Click +Add (left sidebar)
2. Click Import YAML
3. Paste:

apiVersion: v1
kind: Pod
metadata:
  name: upload-helper
  labels:
    app: upload-helper
spec:
  containers:
  - name: helper
    image: registry.access.redhat.com/ubi8/python-39:latest
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: code
      mountPath: /mnt/code-storage
  volumes:
  - name: code
    persistentVolumeClaim:
      claimName: code-storage

4. Click Create

Key YAML Notes:
- kind: Pod - Single container instance (no self-healing or scaling)
- labels - Key-value pairs for organizing/selecting resources
- command: ["sleep", "infinity"] - Overrides container's default CMD to keep pod running
- volumeMounts - Where to mount the volume inside the container (/mnt/code-storage)
- volumes - Defines volume sources; claimName references our PVC

### Wait for Pod Ready
1. Go to Topology view
2. Click on upload-helper circle
3. Wait for pod status to show Running

### Access Terminal and Upload Code
1. Click on pod name in the right panel
2. Click Terminal tab
3. Create the Python scripts:

cd /mnt/code-storage

Create process_data.py:
cat > process_data.py << 'EOF'
#!/usr/bin/env python3
import time
import sys
from datetime import datetime

def main():
    print("=" * 60)
    print("DATA PROCESSING JOB")
    print("=" * 60)
    print(f"Start Time: {datetime.now()}")
    print()

    print("Step 1: Loading data from source...")
    time.sleep(2)
    records = 1000
    print(f"✓ Loaded {records} records")
    print()

    print("Step 2: Processing data in batches...")
    batches = 5
    for i in range(1, batches + 1):
        print(f"  Processing batch {i}/{batches}...")
        time.sleep(1)
    print(f"✓ Processed all {batches} batches")
    print()

    print("Step 3: Generating report...")
    time.sleep(1)
    success = 995
    errors = 5
    print(f"✓ Report generated")
    print()

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
EOF

Create web_server.py:
cat > web_server.py << 'EOF'
#!/usr/bin/env python3
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
EOF

ls -la

Code is now on our persistent volume. This will be available to any pod that mounts this PVC.

---

## PART 3: Run a Job (5 minutes)

### Submit the Job
Jobs run a task once and complete. Perfect for batch processing.

Steps:
1. Click +Add → Import YAML
2. Paste:

apiVersion: batch/v1
kind: Job
metadata:
  name: data-processing-job
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: processor
        image: registry.access.redhat.com/ubi8/python-39:latest
        command: ["python3", "/mnt/code-storage/process_data.py"]
        volumeMounts:
        - name: code
          mountPath: /mnt/code-storage
      volumes:
      - name: code
        persistentVolumeClaim:
          claimName: code-storage

3. Click Create

Key YAML Notes:
- kind: Job - Runs to completion then stops (vs Deployment which runs forever)
- backoffLimit: 0 - Don't retry on failure (set higher for retries)
- restartPolicy: Never - Required for Jobs; don't restart completed containers
- command: ["python3", "/mnt/code-storage/process_data.py"] - Runs the Python script from PVC
- template - Pod template that Job creates; same structure as Pod spec

### Monitor Job
1. Go to Topology view
2. Click on data-processing-job circle
3. Watch status: Pending → Running → Completed

Notice the pod goes from Pending → Running → Completed. That's a Job - runs once and stops.

### Check Logs
1. Click on the pod name in right panel
2. Click Logs tab

We can see it loaded records, processed batches, and generated a report with success rate.

---

## PART 4: Deploy a Service (5 minutes)

### Create Deployment
Deployments keep services always running. They self-heal and can scale.

Steps:
1. Click +Add → Import YAML
2. Paste:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-service
  template:
    metadata:
      labels:
        app: web-service
    spec:
      containers:
      - name: service
        image: registry.access.redhat.com/ubi8/python-39:latest
        command: ["python3", "/mnt/code-storage/web_server.py"]
        volumeMounts:
        - name: code
          mountPath: /mnt/code-storage
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: code
        persistentVolumeClaim:
          claimName: code-storage

3. Click Create

Key YAML Notes:
- kind: Deployment - Manages ReplicaSets; provides self-healing and rolling updates
- replicas: 2 - Number of pod copies to maintain; can scale up/down
- selector.matchLabels - How Deployment finds its pods; MUST match template labels
- command: ["python3", "/mnt/code-storage/web_server.py"] - Runs the Python script from PVC
- readOnly: true - Mount volume as read-only (good for shared code)
- resources.requests - Minimum resources for scheduling (guaranteed)
- resources.limits - Maximum resources allowed (container killed if exceeded for memory)
- cpu: "100m" - 100 millicores = 0.1 CPU core

### Watch Pods
1. Go to Topology view
2. Click on web-service circle
3. Notice the "2" badge showing 2 replicas

Two replicas start up. Notice they stay Running - that's the difference from Jobs.

### Check Logs (Streaming)
1. Click Resources tab in right panel
2. Click on any pod name
3. Click Logs tab

Logs keep streaming because the service is continuously running.

### Test Self-Healing
1. In pod view, click Actions (top right) → Delete Pod
2. Confirm deletion
3. Go back to Topology → click web-service
4. Watch Resources tab

Watch OpenShift automatically create a replacement pod. This is self-healing!

### Scale the Deployment
1. In Topology, click web-service circle
2. In right panel, find Details tab
3. Click up arrow next to pod count to scale to 3
4. Watch 3rd pod appear
5. Click down arrow twice to scale to 1

---

## PART 5: GPU Job (5 minutes)

### Submit GPU Test Job
Now let's run a GPU workload. This tests GPU availability using nvidia-smi.

Steps:
1. Click +Add → Import YAML
2. Paste:

apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-test-job
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: gpu-test
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command:
        - /bin/bash
        - -c
        - |
          echo "=== GPU TEST JOB ==="
          echo "Start: $(date)"
          echo ""
          echo "GPU Information:"
          nvidia-smi --query-gpu=index,name,memory.total,memory.free --format=csv
          echo ""
          echo "Running GPU computation benchmark..."
          python3 -c "
          import torch
          import time

          # Create large tensors on GPU
          size = 4000
          a = torch.randn(size, size, device='cuda')
          b = torch.randn(size, size, device='cuda')

          # Warm up
          c = torch.matmul(a, b)
          torch.cuda.synchronize()

          # Benchmark
          start = time.time()
          for _ in range(50):
              c = torch.matmul(a, b)
          torch.cuda.synchronize()
          elapsed = time.time() - start

          print(f'Matrix size: {size}x{size}')
          print(f'Operations: 50 matrix multiplications')
          print(f'Time: {elapsed:.2f} seconds')
          print(f'TFLOPS: {(2 * size**3 * 50) / elapsed / 1e12:.2f}')
          "
          echo ""
          echo "=== GPU TEST COMPLETED ==="
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"

3. Click Create

Key YAML Notes:
- nvidia.com/gpu: 1 - Request 1 GPU; this is a custom resource type from NVIDIA device plugin
- resources.limits and resources.requests must match for GPUs (they're not divisible)
- tolerations - Allow pod to schedule on GPU nodes that have taints
- key: "nvidia.com/gpu" - Matches the taint applied to GPU nodes
- operator: "Exists" - Tolerate any value for this taint key
- effect: "NoSchedule" - GPU nodes won't accept pods without this toleration

### Monitor GPU Pod
1. Go to Topology view
2. Click on gpu-test-job circle
3. Watch status

The pod may stay Pending briefly while the scheduler finds a GPU node.

### Check GPU Logs
1. Click on pod name in right panel
2. Click Logs tab

Here we see nvidia-smi output showing the GPU model, memory, and CUDA version. This confirms GPU access is working.

Key points to highlight:
- GPU model (e.g., Tesla T4)
- Memory available
- CUDA version

---

## PART 6: GPU Profile Job (Optional - 3 minutes)
For a more realistic test, let's run a PyTorch benchmark.

Steps:
1. Click +Add → Import YAML
2. Paste:

apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-profile-job
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: profiler
        image: pytorch/pytorch:2.1.0-cuda12.1-cudnn8-runtime
        command:
        - python3
        - -c
        - |
          import torch
          import time
          print("=== GPU PROFILE JOB ===")
          print(f"CUDA Available: {torch.cuda.is_available()}")
          print(f"GPU Count: {torch.cuda.device_count()}")
          for i in range(torch.cuda.device_count()):
              props = torch.cuda.get_device_properties(i)
              print(f"GPU {i}: {props.name}, {props.total_memory/1024**3:.1f}GB")

          # Quick benchmark
          a = torch.randn(2000, 2000, device='cuda')
          b = torch.randn(2000, 2000, device='cuda')
          start = time.time()
          for _ in range(100):
              c = torch.matmul(a, b)
          torch.cuda.synchronize()
          print(f"Matrix multiply benchmark: {time.time()-start:.2f}s")
          print("=== PROFILE COMPLETE ===")
        resources:
          limits:
            nvidia.com/gpu: 1
          requests:
            nvidia.com/gpu: 1
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"

3. Click Create
4. View logs once completed

Key YAML Notes:
- image: pytorch/pytorch:... - Pre-built image with CUDA, cuDNN, and PyTorch
- command: [python3, -c, |...] - Run inline Python script
- Same GPU resource/toleration pattern as gpu-test-job
- No volumeMounts needed - this job runs self-contained in memory

---

## PART 7: Cleanup (2 minutes)

### Delete Resources
1. Topology view → click each resource → Actions → Delete

Or use Administrator perspective:
1. Workloads → Jobs → Delete jobs
2. Workloads → Deployments → Delete web-service
3. Workloads → Pods → Delete upload-helper
4. Storage → PersistentVolumeClaims → Delete code-storage (if done)

---

## Summary (1 minute)
Let's recap what we covered:

Workload          Purpose                  Behavior
PVC               Persistent storage       Data survives pod restarts
Job               One-time tasks           Runs → Completes → Stops
Deployment        Always-on services       Runs forever, self-heals, scales
GPU Job           GPU workloads            Requests nvidia.com/gpu resource

Everything we did today was through the OpenShift Web Console - no CLI needed!

---

## UI Navigation Quick Reference

Task                    Navigation
Create resource         +Add → Import YAML
View topology           Left sidebar → Topology
See pod logs            Click pod → Logs tab
Access terminal         Click pod → Terminal tab
Check events            Click pod → Events tab
Scale deployment        Topology → click deployment → Details → arrows
Delete resource         Click resource → Actions → Delete

---

## Troubleshooting Quick Reference

Pod stuck in Pending:
- Click pod → Events tab
- Look for scheduling errors

Image pull errors:
- Check Events tab for "ImagePullBackOff"
- Verify image name is correct

Job failed:
- Check Logs tab for errors
- Job shows 0/1 completions

---

## Pre-Demo Checklist

[ ] OpenShift Console open
[ ] Logged in with correct user
[ ] Developer perspective selected
[ ] Correct project/namespace selected
[ ] GPU nodes available (for GPU section)
[ ] Previous demo resources cleaned up

---

## PART 8: Monitoring & Alerting (10 minutes)

### Deploy Grafana Dashboard
"Now let's set up monitoring with Grafana dashboards and alerts that can notify us via Google Chat."

Steps:
1. Click +Add → Import YAML
2. Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-pods
  namespace: basic-lab
  labels:
    grafana_dashboard: "1"
data:
  pods-dashboard.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "panels": [
        {
          "datasource": {"type": "prometheus", "uid": "prometheus"},
          "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
          "id": 1,
          "targets": [{"expr": "count(up == 1)", "refId": "A"}],
          "title": "Total Running Targets",
          "type": "stat"
        },
        {
          "datasource": {"type": "prometheus", "uid": "prometheus"},
          "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
          "id": 2,
          "targets": [{"expr": "up", "legendFormat": "{{job}}", "refId": "A"}],
          "title": "Target Status Over Time",
          "type": "timeseries"
        }
      ],
      "refresh": "5s",
      "title": "Pod Monitoring Dashboard",
      "uid": "pod-monitoring"
    }
```

3. Click Create
4. Restart Grafana: Go to Workloads → Deployments → grafana → Actions → Restart

Key YAML Notes:
- kind: ConfigMap - Stores dashboard JSON that Grafana loads on startup
- labels.grafana_dashboard: "1" - Label that tells Grafana to import this dashboard
- datasource.uid: "prometheus" - References the Prometheus data source
- expr: "up" - PromQL query for target health

---

### Create Metric-Based Alerts
"Next, let's create Prometheus alert rules that trigger when conditions are met."

Steps:
1. Click +Add → Import YAML
2. Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alert-rules
  namespace: basic-lab
  labels:
    app: prometheus
data:
  alerts.yml: |
    groups:
      - name: demo-alerts
        rules:
          - alert: TargetDown
            expr: up == 0
            for: 30s
            labels:
              severity: critical
            annotations:
              summary: "Target {{ $labels.job }} is down"
              description: "Target {{ $labels.instance }} has been down for 30s"

          - alert: PodCreated
            expr: count(up) > 0
            for: 10s
            labels:
              severity: info
            annotations:
              summary: "Target up"
              description: "{{ $value }} active targets being monitored"

          - alert: HighMemoryUsage
            expr: up == 1
            for: 10s
            labels:
              severity: warning
            annotations:
              summary: "Memory usage > 10MB"
              description: "Simulated high memory alert for demo"
```

3. Click Create
4. Restart Prometheus: Go to Workloads → Deployments → prometheus → Actions → Restart

Key YAML Notes:
- groups - Collection of related alert rules
- expr: up == 0 - PromQL expression that triggers alert when true
- for: 30s - Duration condition must be true before firing
- labels.severity - Used for routing alerts (critical, warning, info)
- annotations - Human-readable messages with template variables like {{ $labels.job }}

---

### Create Log-Based Alert (Grafana)
"For log-based alerting, we can create rules in Grafana that query Elasticsearch."

Steps:
1. Click +Add → Import YAML
2. Paste:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alert-rules
  namespace: basic-lab
  labels:
    grafana_alert: "1"
data:
  alert-rules.yaml: |
    apiVersion: 1
    groups:
      - orgId: 1
        name: log-alerts
        folder: Demo Alerts
        interval: 1m
        rules:
          - uid: log-error-alert
            title: Log Error Alert
            condition: C
            data:
              - refId: A
                datasourceUid: prometheus
                model:
                  expr: up == 1
            for: 10s
            annotations:
              summary: Log-based alert triggered
              description: This alert fires on log errors
            labels:
              severity: warning
```

3. Click Create
4. Restart Grafana

Key YAML Notes:
- interval: 1m - How often to evaluate the rule
- condition: C - Which data query result triggers the alert
- datasourceUid - Reference to data source (prometheus, elasticsearch)
- for: 10s - Pending period before alert fires

---

### Configure Google Chat Notifications
"Finally, let's send alerts to Google Chat."

Steps in Grafana UI:
1. Access Grafana (https://grafana-basic-lab.apps.rosa.ukhsa-rosa-eu1.j5jq.p3.openshiftapps.com)
2. Login: admin / admin
3. Go to Alerting → Contact points → Add contact point
4. Name: Google Chat
5. Integration: Google Hangouts Chat
6. URL: Your Google Chat webhook URL
7. Save contact point
8. Go to Alerting → Notification policies
9. Edit default policy → Change contact point to "Google Chat"
10. Save

Now all firing alerts will be sent to your Google Chat space!

---

## Monitoring Summary

Resource Type          Purpose                       Apply Command
ConfigMap (dashboard)  Grafana dashboard             oc apply -f grafana-dashboard-configmap.yaml
ConfigMap (alerts)     Prometheus alert rules        oc apply -f prometheus-alert-rules.yaml
ConfigMap (log alerts) Grafana log-based alerts      oc apply -f grafana-log-alert.yaml

After applying ConfigMaps, restart the corresponding deployment:
- oc rollout restart deployment/grafana -n basic-lab
- oc rollout restart deployment/prometheus -n basic-lab

---

## Files Location

All monitoring YAML files are in: /workspaces/dareoke/basic-lab-monitoring/
- grafana-dashboard-configmap.yaml
- prometheus-alert-rules.yaml
- grafana-log-alert.yaml

---

END OF SPEAKER NOTES
