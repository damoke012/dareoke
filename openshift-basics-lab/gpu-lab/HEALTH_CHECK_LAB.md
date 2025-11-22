# Health Check Lab - Complete Guide

This guide covers deploying a health check service, monitoring with dashboards, and creating alerts for OpenShift/ROSA clusters.

---

## Health Check Deployment

### The Complete Health Check Deployment YAML

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-check
  labels:
    app: health-check
spec:
  replicas: 2
  selector:
    matchLabels:
      app: health-check
  template:
    metadata:
      labels:
        app: health-check
    spec:
      containers:
      - name: health-check
        image: nginx:alpine
        ports:
        - name: http
          containerPort: 80
        resources:
          limits:
            memory: "128Mi"
            cpu: "100m"
          requests:
            memory: "64Mi"
            cpu: "50m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
```

### What the Health Check Does

The health-check deployment creates a simple nginx container with probes for monitoring.

**How It Works:**
1. Runs nginx web server on port 80
2. Liveness probe checks if container is healthy
3. Readiness probe checks if container can receive traffic
4. Resource limits ensure predictable CPU/memory usage

**Metrics Available via Prometheus:**

| Metric | Source | Description |
|--------|--------|-------------|
| `kube_pod_info` | kube-state-metrics | Pod information and status |
| `kube_pod_container_status_ready` | kube-state-metrics | Container readiness state |
| `kube_pod_container_status_restarts_total` | kube-state-metrics | Container restart count |
| `container_memory_usage_bytes` | cAdvisor | Current memory usage |
| `container_cpu_usage_seconds_total` | cAdvisor | CPU time consumed |

### How to Deploy

1. **Workloads → Deployments**
2. Click **Create Deployment**
3. Delete the default YAML and paste the manifest above
4. Click **Create**

### Verify Deployment

1. **Workloads → Deployments** → `health-check`
2. Check **Pods** tab - should show 2/2 Running
3. View **Logs** for nginx output

### Check Events

1. **Workloads → Pods** → `health-check-xxxxx`
2. Click **Events** tab
3. Review Events for:
   - Scheduled - Pod assigned to node
   - Pulled - Image downloaded
   - Started - Container running

---

## Health Check Service

### The Complete Service YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: health-check
  labels:
    app: health-check
spec:
  ports:
  - name: http
    port: 80
    targetPort: 80
  selector:
    app: health-check
```

### How to Create Service

1. **Networking → Services**
2. Click **Create Service**
3. Delete the default YAML and paste the manifest above
4. Click **Create**

### Verify Service

1. **Networking → Services** → `health-check`
2. Check **Pods** tab - should show 2 pods
3. Click on a Pod and view **Logs**

### Check Events

1. **Workloads → Pods** → `health-check-xxxxx`
2. Click **Events** tab
3. Review Events

**Note:** Review Scaling up and Self Healing capabilities by:
- Scaling replicas up/down via Deployments
- Deleting a pod to see Kubernetes recreate it automatically

---

## Profiling & Monitoring

### Health Check Alerts

Since PrometheusRule CRD requires cluster-admin permissions, create alerts directly in Grafana UI.

**Alert 1: Pods Running Test Alert** (will fire when health-check pods exist)

| Field | Value |
|-------|-------|
| Name | HealthCheckPodsRunning |
| Query | `count(kube_pod_info{namespace="basic-lab", pod=~"health-check.*"}) > 0` |
| Condition | IS ABOVE 0 |
| For | 1m |
| Labels | severity=info, team=gpu-lab |
| Summary | Health Check pods are running in basic-lab |
| Description | This test alert fires when health-check pods are running. Pod count: {{ $value }} |

**Alert 2: High Memory Usage** (fires immediately - low threshold)

| Field | Value |
|-------|-------|
| Name | HealthCheckHighMemory |
| Query | `container_memory_usage_bytes{namespace="basic-lab", pod=~"health-check.*", container!=""} > 1000000` |
| Condition | IS ABOVE 1000000 (1MB) |
| For | 1m |
| Labels | severity=warning, team=gpu-lab |
| Summary | Health Check pod high memory usage |
| Description | Container {{ $labels.container }} in pod {{ $labels.pod }} is using high memory |

**Alert 3: Container Restarts**

| Field | Value |
|-------|-------|
| Name | HealthCheckRestarts |
| Query | `increase(kube_pod_container_status_restarts_total{namespace="basic-lab", pod=~"health-check.*"}[5m]) > 0` |
| Condition | IS ABOVE 0 |
| For | 1m |
| Labels | severity=warning, team=gpu-lab |
| Summary | Health Check container restarted |
| Description | Container {{ $labels.container }} in pod {{ $labels.pod }} has restarted |

### How to Create Alerts in Grafana

1. **Alerting → Alert rules**
2. Click **New alert rule**
3. Select **Grafana managed alert**
4. Configure:
   - Enter the query from table above
   - Set evaluation interval to 1m
   - Add labels (severity, team)
   - Add annotations (summary, description)
5. Click **Save and exit**

### Verify Alerts

1. Open **Grafana → Alerting → Alert rules**
2. You should see the alerts listed
3. The `HealthCheckPodsRunning` alert will fire when pods exist - use this to test Google Chat notifications

### Test Alert Flow

1. Create the alert in Grafana
2. Deploy the health-check pods
3. Wait 1 minute for `HealthCheckPodsRunning` to fire
4. Check **Grafana → Alerting → Alert rules** - should show "Firing"
5. Check Google Chat - notification should arrive

---

## Dashboard

### Import Dashboard

1. **Grafana → Dashboards → Import**
2. Upload `health-check-dashboard.json` or paste its content
3. Select **Prometheus** as the datasource
4. Click **Import**

### Dashboard Panels

| Panel | Query | Description |
|-------|-------|-------------|
| Running Pods | `count(kube_pod_info{namespace="basic-lab", pod=~"health-check.*"})` | Number of health-check pods |
| Ready Containers | `count(kube_pod_container_status_ready{namespace="basic-lab", pod=~"health-check.*"})` | Containers that are ready |
| Container Restarts | `sum(kube_pod_container_status_restarts_total{namespace="basic-lab", pod=~"health-check.*"})` | Total restart count |
| Memory Usage | `container_memory_usage_bytes{namespace="basic-lab", pod=~"health-check.*"}` | Memory per container |
| CPU Usage | `rate(container_cpu_usage_seconds_total{namespace="basic-lab", pod=~"health-check.*"}[5m])` | CPU rate per container |

---

## Google Chat Integration

### Configure Contact Point

1. **Grafana → Alerting → Contact points**
2. Click **Add contact point**
3. Configure:
   - Name: `Google Chat`
   - Integration type: **Google Hangouts Chat** (or Webhook)
   - URL: Your Google Chat webhook URL
4. Click **Save contact point**

### Configure Notification Policy

1. **Grafana → Alerting → Notification policies**
2. Edit default policy or add new one
3. Set contact point to **Google Chat**
4. Save

### Test Notification

1. Ensure health-check pods are deployed
2. Create `HealthCheckPodsRunning` alert
3. Alert should fire within 1-2 minutes
4. Check Google Chat for notification

---

## Quick Reference

| Task | Location |
|------|----------|
| Deploy Health Check | Workloads → Deployments → Create Deployment |
| Create Service | Networking → Services → Create Service |
| Create Alert | Grafana → Alerting → Alert rules → New |
| Import Dashboard | Grafana → Dashboards → Import |
| Configure Google Chat | Grafana → Alerting → Contact points |
| View Pod Logs | Workloads → Pods → [pod] → Logs |
| Check Alert Status | Grafana → Alerting → Alert rules |

---

## Files in This Lab

| File | Purpose |
|------|---------|
| `health-check-deployment.yaml` | Deployment + Service for health check |
| `health-check-dashboard.json` | Grafana dashboard JSON |
| `health-check-alerts.yaml` | Alert configuration reference |
| `HEALTH_CHECK_LAB.md` | This documentation |
