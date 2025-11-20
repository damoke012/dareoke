# Container Transfer Guide for Ansuya

## Objective
Save the working GCP Jupyter notebook container (with all fixed dependencies) to OpenShift's internal registry so we can run it directly without rebuilding.

---

## Plan A Failed: OpenShift Build Dependencies Issues ❌
We tried building the parabricks container on OpenShift but kept hitting dependency issues.

## Plan B: Transfer Working Container from GCP ✅

### Why This Works
- GCP Jupyter notebook already has all dependencies working
- We pull the exact container that works
- Push it to OpenShift's internal registry (Harbor or OpenShift registry)
- Run it directly - no rebuilding, no dependency issues

---

## Step 1: Deploy the Transfer Pod

From your local machine (with oc access):

```bash
# Create the pod with podman/skopeo for container operations
oc apply -f ansuya-container-transfer-pod.yaml -n parabricks
```

Wait for pod to be ready:

```bash
oc get pods -n parabricks -l user=ansuya
```

---

## Step 2: Shell into the Transfer Pod

```bash
oc rsh -n parabricks ansuya-container-transfer
```

---

## Step 3: Authenticate to GCP

Inside the pod:

```bash
# Install gcloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Authenticate
gcloud auth login --no-launch-browser
# Follow the browser authentication flow

# Set project
gcloud config set project YOUR_GCP_PROJECT_ID

# Configure Docker auth for GCR
gcloud auth configure-docker
```

---

## Step 4: Find Your GCP Jupyter Container Image

You need to identify the exact container image Ansuya is using in GCP Vertex AI Workbench.

### Option A: From GCP Console
1. Go to Vertex AI Workbench
2. Click on the notebook instance
3. Look for "Container Image" - it will be something like:
   - `gcr.io/deeplearning-platform-release/base-cpu`
   - `gcr.io/PROJECT_ID/custom-notebook:tag`
   - Or a custom image

### Option B: From Inside the Running GCP Notebook

If Ansuya can run this in her GCP Jupyter terminal:

```bash
# Find the container image
cat /etc/hostname  # Get container ID
docker inspect $(hostname) | grep Image

# Or check environment
env | grep IMAGE
```

---

## Step 5: Pull the GCP Container Image

Inside the transfer pod:

```bash
# Example - replace with actual image
podman pull gcr.io/deeplearning-platform-release/tf2-gpu.2-13:latest

# Or if it's a custom image
podman pull gcr.io/YOUR_PROJECT/parabricks-notebook:latest
```

---

## Step 6: Save Container to OpenShift Registry

### Option A: Push to OpenShift Internal Registry

```bash
# Login to OpenShift registry
oc login --token=YOUR_TOKEN --server=https://api.lab.ocp.lan:6443

# Get registry route
REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')

# Login to registry
podman login -u $(oc whoami) -p $(oc whoami -t) $REGISTRY

# Tag the image
podman tag gcr.io/PROJECT/image:tag $REGISTRY/parabricks/parabricks-workbench:gcp-working

# Push to OpenShift registry
podman push $REGISTRY/parabricks/parabricks-workbench:gcp-working
```

### Option B: Push to Harbor Registry (if deployed)

```bash
# Login to Harbor
podman login harbor.apps.lab.ocp.lan -u admin

# Tag for Harbor
podman tag gcr.io/PROJECT/image:tag harbor.apps.lab.ocp.lan/library/parabricks-workbench:gcp-working

# Push to Harbor
podman push harbor.apps.lab.ocp.lan/library/parabricks-workbench:gcp-working
```

---

## Step 7: Save Container as Tar Archive (Backup Method)

If you want to save it to the PVC for backup:

```bash
# Save to tar file
podman save gcr.io/PROJECT/image:tag -o /data/parabricks-gcp-container.tar

# Compress it
gzip /data/parabricks-gcp-container.tar

# Check size
ls -lh /data/parabricks-gcp-container.tar.gz
```

Later, you can load it:

```bash
podman load -i /data/parabricks-gcp-container.tar.gz
```

---

## Step 8: Create Deployment Using the Transferred Image

Create `parabricks-workbench-from-gcp.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: parabricks-workbench-gcp
  namespace: parabricks
spec:
  serviceName: parabricks-workbench-gcp
  replicas: 1
  selector:
    matchLabels:
      app: parabricks-workbench-gcp
  template:
    metadata:
      labels:
        app: parabricks-workbench-gcp
    spec:
      containers:
      - name: notebook
        # Use the image we just pushed
        image: image-registry.openshift-image-registry.svc:5000/parabricks/parabricks-workbench:gcp-working
        imagePullPolicy: Always
        ports:
        - containerPort: 8888
          name: notebook
        volumeMounts:
        - name: data
          mountPath: /home/jovyan/work  # Adjust to match GCP mount point
        - name: notebook-storage
          mountPath: /home/jovyan
        resources:
          requests:
            memory: "8Gi"
            cpu: "2"
            nvidia.com/gpu: "1"  # If GPU needed
          limits:
            memory: "16Gi"
            cpu: "4"
            nvidia.com/gpu: "1"
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: parabricks-data
  volumeClaimTemplates:
  - metadata:
      name: notebook-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: parabricks-workbench-gcp
  namespace: parabricks
spec:
  selector:
    app: parabricks-workbench-gcp
  ports:
  - port: 8888
    targetPort: 8888
    name: notebook
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: parabricks-workbench-gcp
  namespace: parabricks
spec:
  to:
    kind: Service
    name: parabricks-workbench-gcp
  port:
    targetPort: notebook
  tls:
    termination: edge
```

Deploy it:

```bash
oc apply -f parabricks-workbench-from-gcp.yaml -n parabricks
```

---

## Step 9: Access the Workbench

```bash
# Get the route URL
oc get route parabricks-workbench-gcp -n parabricks

# Open in browser
echo "https://$(oc get route parabricks-workbench-gcp -n parabricks -o jsonpath='{.spec.host}')"
```

---

## Alternative: Use Skopeo for Direct Registry-to-Registry Copy

If both registries are accessible from the pod:

```bash
# Install skopeo (should already be in the podman image)
skopeo --version

# Copy directly from GCR to OpenShift registry
skopeo copy \
  --src-creds=$(gcloud auth print-access-token) \
  --dest-creds=$(oc whoami):$(oc whoami -t) \
  docker://gcr.io/PROJECT/image:tag \
  docker://default-route-openshift-image-registry.apps.lab.ocp.lan/parabricks/parabricks-workbench:gcp-working
```

---

## Troubleshooting

### Issue: "Permission denied" when pushing to registry

**Solution**: Ensure the service account has image-builder role:

```bash
oc policy add-role-to-user system:image-builder -z parabricks-builder -n parabricks
```

### Issue: "No space left on device"

**Solution**: The emptyDir volume is full. Increase the `sizeLimit` in the pod YAML or use the tar archive method to save directly to PVC.

### Issue: Can't find the GCP image name

**Solution**:
1. Ask Ansuya to run this in her GCP notebook terminal: `env | grep IMAGE`
2. Or check the Vertex AI Workbench instance details in GCP Console
3. Common images:
   - `gcr.io/deeplearning-platform-release/base-cpu`
   - `gcr.io/deeplearning-platform-release/tf2-gpu.2-13`
   - `gcr.io/deeplearning-platform-release/pytorch-gpu.1-13`

### Issue: GCP authentication not working

**Solution**: Use a service account key instead:

```bash
# Download service account key from GCP
# Copy to pod
oc cp /path/to/key.json parabricks/ansuya-container-transfer:/tmp/key.json

# In pod
gcloud auth activate-service-account --key-file=/tmp/key.json
```

---

## Summary

**What this achieves:**
1. ✅ Pull the exact working container from GCP (with all dependencies fixed)
2. ✅ Push it to OpenShift registry
3. ✅ Run it directly on OpenShift without rebuilding
4. ✅ Avoid all the dependency issues we had with Plan A

**Next steps for Ansuya:**
1. Deploy the transfer pod
2. Identify her GCP notebook container image
3. Pull and push to OpenShift registry
4. Deploy the workbench using the transferred image
5. Start working with parabricks pipelines on OpenShift

---

## Quick Commands Reference

```bash
# Deploy transfer pod
oc apply -f ansuya-container-transfer-pod.yaml -n parabricks

# Shell into pod
oc rsh -n parabricks ansuya-container-transfer

# Pull from GCP
podman pull gcr.io/PROJECT/image:tag

# Tag for OpenShift
podman tag gcr.io/PROJECT/image:tag image-registry.openshift-image-registry.svc:5000/parabricks/workbench:gcp

# Push to OpenShift
podman push image-registry.openshift-image-registry.svc:5000/parabricks/workbench:gcp

# Deploy workbench
oc apply -f parabricks-workbench-from-gcp.yaml -n parabricks

# Get workbench URL
oc get route parabricks-workbench-gcp -n parabricks
```
