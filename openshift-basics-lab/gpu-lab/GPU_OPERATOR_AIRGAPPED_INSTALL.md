# GPU Operator Installation in Air-Gapped OpenShift Environment

## Overview
This documents the installation of NVIDIA GPU Operator in an air-gapped OpenShift environment with Harbor registry.

**Date:** December 5, 2025
**Environment:** OpenShift 4.x, Harbor registry at `harbor.apps.lab.ocp.lan`
**GPU:** Tesla P40 (24GB) passed through from ESXi 8.0.2

## Prerequisites Completed
- ESXi GPU passthrough configured (see `ESXI_GPU_PASSTHROUGH_GUIDE.md`)
- GPU visible in VM at PCI address `0000:13:00.0`
- Harbor registry accessible with credentials

## Step 1: Install Node Feature Discovery (NFD) Operator

```bash
# Install via OperatorHub in OpenShift Console
# Or via CLI:
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

## Step 2: Mirror NVIDIA Images to Harbor

### Login to registries
```bash
# Login to NVIDIA registry
docker login nvcr.io -u '$oauthtoken' -p <NGC_API_KEY>

# Login to Harbor
docker login harbor.apps.lab.ocp.lan -u admin -p Harbor12345
```

### Mirror required images
```bash
# GPU Operator
docker pull nvcr.io/nvidia/gpu-operator:v24.9.2
docker tag nvcr.io/nvidia/gpu-operator:v24.9.2 harbor.apps.lab.ocp.lan/nvidia/gpu-operator:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/gpu-operator:v24.9.2

# Device Plugin
docker pull nvcr.io/nvidia/k8s-device-plugin:v24.9.2
docker tag nvcr.io/nvidia/k8s-device-plugin:v24.9.2 harbor.apps.lab.ocp.lan/nvidia/k8s-device-plugin:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/k8s-device-plugin:v24.9.2

# Container Toolkit
docker pull nvcr.io/nvidia/k8s/container-toolkit:v24.9.2
docker tag nvcr.io/nvidia/k8s/container-toolkit:v24.9.2 harbor.apps.lab.ocp.lan/nvidia/container-toolkit:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/container-toolkit:v24.9.2

# Validator
docker pull nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.2
docker tag nvcr.io/nvidia/cloud-native/gpu-operator-validator:v24.9.2 harbor.apps.lab.ocp.lan/nvidia/gpu-operator-validator:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/gpu-operator-validator:v24.9.2

# DCGM
docker pull nvcr.io/nvidia/cloud-native/dcgm:3.3.9-1-ubuntu22.04
docker tag nvcr.io/nvidia/cloud-native/dcgm:3.3.9-1-ubuntu22.04 harbor.apps.lab.ocp.lan/nvidia/dcgm:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/dcgm:v24.9.2

# DCGM Exporter
docker pull nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04
docker tag nvcr.io/nvidia/k8s/dcgm-exporter:3.3.9-3.6.1-ubuntu22.04 harbor.apps.lab.ocp.lan/nvidia/dcgm-exporter:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/dcgm-exporter:v24.9.2

# Driver Manager
docker pull nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0
docker tag nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.7.0 harbor.apps.lab.ocp.lan/nvidia/k8s-driver-manager:v24.9.2
docker push harbor.apps.lab.ocp.lan/nvidia/k8s-driver-manager:v24.9.2

# Driver (pull by digest for RHEL 9.6)
docker pull nvcr.io/nvidia/driver@sha256:6fe74322562c726c8fade184d8c45ebae3da7b1ea0a21f0ff9dc42c66c65e692
docker tag nvcr.io/nvidia/driver@sha256:6fe74322562c726c8fade184d8c45ebae3da7b1ea0a21f0ff9dc42c66c65e692 harbor.apps.lab.ocp.lan/nvidia/driver:550.127.08
docker push harbor.apps.lab.ocp.lan/nvidia/driver:550.127.08
```

## Step 3: Install GPU Operator from OperatorHub

Install the NVIDIA GPU Operator from OperatorHub in the OpenShift Console.

## Step 4: Create ClusterPolicy with Harbor Registry

```yaml
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
    use_ocp_driver_toolkit: true
  daemonsets:
    updateStrategy: RollingUpdate
    rollingUpdate:
      maxUnavailable: "1"
  driver:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: driver
    version: "550.127.08"
  toolkit:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: container-toolkit
    version: v24.9.2
  devicePlugin:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: k8s-device-plugin
    version: v24.9.2
  dcgm:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: dcgm
    version: v24.9.2
  dcgmExporter:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: dcgm-exporter
    version: v24.9.2
  gfd:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: k8s-device-plugin
    version: v24.9.2
  validator:
    enabled: true
    repository: harbor.apps.lab.ocp.lan/nvidia
    image: gpu-operator-validator
    version: v24.9.2
```

Apply with:
```bash
oc apply -f clusterpolicy.yaml
```

## Current Issue: ESXi BAR Memory Mapping

The driver compiled successfully but GPU BAR memory regions are not mapped:
```
NVRM: BAR1 is 0M @ 0x0 (PCI:0000:13:00.0)
NVRM: BAR2 is 0M @ 0x0 (PCI:0000:13:00.0)
NVRM: BAR5 is 0M @ 0x0 (PCI:0000:13:00.0)
```

### Fix Required

1. **Shut down ocp-w-1 VM**

2. **Edit VMX file on ESXi host:**
```bash
vim /vmfs/volumes/datastore1/ocp-w-1/ocp-w-1.vmx
```

3. **Add these lines:**
```
pciPassthru.use64bitMMIO = "TRUE"
pciPassthru.64bitMMIOSizeGB = "64"
pciPassthru0.msiEnabled = "TRUE"
```

4. **Power on the VM**

5. **Verify GPU works:**
```bash
oc debug node/ocp-w-1.lab.ocp.lan -- chroot /host nvidia-smi
```

## Verification Commands

```bash
# Check GPU Operator pods
oc get pods -n nvidia-gpu-operator

# Check GPU resources on node
oc describe node ocp-w-1.lab.ocp.lan | grep -A5 "Allocatable:" | grep nvidia

# Test GPU workload
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0-base
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
```

## Next Steps After Fix
1. Verify all GPU Operator pods are Running
2. Confirm `nvidia.com/gpu: 1` in node allocatable resources
3. Deploy TensorRT-LLM model build job
4. Deploy Triton Inference Server
