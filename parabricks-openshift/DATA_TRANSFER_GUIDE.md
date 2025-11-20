# GCP to OpenShift Data Transfer Guide

This guide provides multiple methods to transfer Anasuya's genomics data from GCS bucket to the OpenShift parabricks-data PVC (100GB).

**Source**: `gs://anasuya_backups/Parabricks_Pathogentest/Parabricks_pathogen_Test` (42GB)
**Destination**: `parabricks-data` PVC in `parabricks` namespace

---

## Option 1: Interactive Transfer Pod (Recommended for First Time)

Use this method if you want full control and can authenticate interactively.

### Step 1: Create the transfer pod

```bash
oc apply -f gcs-data-transfer-pod.yaml -n parabricks
```

### Step 2: Wait for pod to be ready

```bash
oc get pods -n parabricks -l app=data-transfer
```

Wait until status shows `Running`.

### Step 3: Open a shell in the pod

```bash
oc rsh -n parabricks gcs-data-transfer
```

### Step 4: Authenticate with GCP

Inside the pod, run:

```bash
gcloud auth login --no-launch-browser
```

Follow the instructions:
1. Copy the URL provided
2. Open it in your browser
3. Authenticate with your GCP account
4. Copy the verification code
5. Paste it back in the terminal

### Step 5: Set your GCP project

```bash
gcloud config set project YOUR_PROJECT_ID
```

### Step 6: Transfer the data

```bash
# Transfer all files from the GCS bucket to the PVC
gsutil -m cp -r gs://anasuya_backups/Parabricks_Pathogentest/Parabricks_pathogen_Test/* /data/
```

The `-m` flag enables parallel multi-threaded transfer for faster speeds.

### Step 7: Verify the transfer

```bash
# Check what was transferred
ls -lh /data/

# Check total size
du -sh /data/*
du -sh /data
```

### Step 8: Exit and clean up

```bash
exit  # Exit the pod shell

# Delete the transfer pod
oc delete pod gcs-data-transfer -n parabricks
```

---

## Option 2: Automated Transfer Job (Using Service Account)

Use this method for automated, repeatable transfers.

### Prerequisites

You need a GCP service account key file with permissions to read from the GCS bucket.

### Step 1: Create the service account key secret

```bash
# Download your service account key from GCP Console
# Then create a secret in OpenShift
oc create secret generic gcp-service-account-key \
  --from-file=key.json=/path/to/your/service-account-key.json \
  -n parabricks
```

### Step 2: Update the Job configuration

Edit `gcs-data-transfer-job.yaml` and update:

```yaml
env:
- name: GCP_PROJECT_ID
  value: "your-actual-gcp-project-id"  # Change this
```

### Step 3: Run the transfer job

```bash
oc apply -f gcs-data-transfer-job.yaml -n parabricks
```

### Step 4: Monitor the job

```bash
# Watch job status
oc get jobs -n parabricks -w

# View logs
oc logs -f job/gcs-data-transfer-job -n parabricks
```

### Step 5: Verify completion

```bash
# Check job status
oc get job gcs-data-transfer-job -n parabricks

# If successful, check the data in the workbench
oc rsh -n parabricks parabricks-workbench-0
ls -lh /mnt/data/
```

### Step 6: Clean up

```bash
# Delete the job (keeps the data)
oc delete job gcs-data-transfer-job -n parabricks
```

---

## Option 3: Transfer from Jupyter Workbench Terminal

If you prefer to do everything from the workbench itself:

### Step 1: Ensure the PVC is mounted to the workbench

First, check if the StatefulSet has the PVC mounted. If not, add this to `parabricks-workbench-statefulset.yaml`:

```yaml
volumes:
- name: data
  persistentVolumeClaim:
    claimName: parabricks-data
```

And in the container spec:

```yaml
volumeMounts:
- name: data
  mountPath: /mnt/data
```

### Step 2: Open terminal in Jupyter workbench

Access the workbench UI and open a terminal.

### Step 3: Install gcloud CLI

```bash
# Install gcloud in the terminal
curl https://sdk.cloud.google.com | bash
exec -l $SHELL  # Restart shell

# Initialize gcloud
gcloud init --console-only
```

### Step 4: Authenticate

```bash
gcloud auth login --no-launch-browser
```

### Step 5: Transfer data

```bash
gsutil -m cp -r gs://anasuya_backups/Parabricks_Pathogentest/Parabricks_pathogen_Test/* /mnt/data/
```

---

## Option 4: Download Locally, Then Upload

If GCS access from OpenShift is restricted:

### Step 1: Download from GCS to your local machine

```bash
# On your local machine
gsutil -m cp -r gs://anasuya_backups/Parabricks_Pathogentest/Parabricks_pathogen_Test ./local-data/
```

### Step 2: Compress the data

```bash
tar -czf pathogen-test-data.tar.gz ./local-data/
```

### Step 3: Use oc rsync to upload

```bash
# Create upload pod
oc run data-upload --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --command -- sleep infinity \
  -n parabricks

# Wait for pod to be ready
oc wait --for=condition=Ready pod/data-upload -n parabricks

# Attach the PVC to the pod
oc set volume pod/data-upload --add \
  --name=data \
  --type=persistentVolumeClaim \
  --claim-name=parabricks-data \
  --mount-path=/data \
  -n parabricks

# Upload the data
oc rsync ./local-data/ data-upload:/data/ -n parabricks

# Clean up
oc delete pod data-upload -n parabricks
```

---

## Verifying Data in the Workbench

After transfer completes, verify the data is accessible from the workbench:

### Step 1: Mount the PVC to workbench (if not already mounted)

Update the workbench StatefulSet to include:

```yaml
volumes:
- name: genomics-data
  persistentVolumeClaim:
    claimName: parabricks-data

# In container volumeMounts:
volumeMounts:
- name: genomics-data
  mountPath: /mnt/data
```

Apply the changes:

```bash
oc apply -f parabricks-workbench-statefulset.yaml -n parabricks
oc rollout restart statefulset/parabricks-workbench -n parabricks
```

### Step 2: Verify from workbench terminal

Open a terminal in the Jupyter workbench and run:

```bash
# List transferred files
ls -lh /mnt/data/

# Check total size
du -sh /mnt/data

# Verify specific genomics files
ls /mnt/data/*.fasta
ls /mnt/data/*.fastq
ls /mnt/data/*.bam
```

---

## Troubleshooting

### Issue: "Permission denied" errors

**Solution**: Ensure the GCP service account has `Storage Object Viewer` or `Storage Object Admin` role.

```bash
# Grant permissions (run in GCP Cloud Shell)
gsutil iam ch serviceAccount:YOUR-SA@PROJECT.iam.gserviceaccount.com:objectViewer \
  gs://anasuya_backups
```

### Issue: Transfer is very slow

**Solution**: Use the `-m` flag for parallel transfer:

```bash
gsutil -m -o GSUtil:parallel_thread_count=10 cp -r gs://bucket/* /data/
```

### Issue: Out of disk space

**Solution**: Check PVC size:

```bash
# Check PVC capacity
oc get pvc parabricks-data -n parabricks

# If needed, expand PVC (if storage class supports it)
oc patch pvc parabricks-data -n parabricks -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

### Issue: Cannot access PVC from workbench

**Solution**: Ensure PVC is mounted:

```bash
# Check if volume is mounted
oc describe pod parabricks-workbench-0 -n parabricks | grep -A 5 "Volumes:"

# Check mount points inside pod
oc rsh -n parabricks parabricks-workbench-0 df -h
```

---

## Recommended Approach

For Anasuya's 42GB dataset, I recommend:

1. **First time**: Use **Option 1 (Interactive Transfer Pod)** for full control and visibility
2. **Subsequent transfers**: Use **Option 2 (Automated Job)** for repeatability
3. **Small files or testing**: Use **Option 3 (From Workbench)** for convenience

The 100GB PVC (`parabricks-data`) is already created and ready to receive the data.
