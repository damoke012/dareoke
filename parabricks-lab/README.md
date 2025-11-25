# Ansuya's Parabricks Docker-in-Docker Workbench

Complete package for deploying Ansuya's genomics workbench with Docker-in-Docker support.

## Contents

```
ansuya-dind-package/
├── README.md           # This file
├── Dockerfile          # Docker image with Parabricks, Docker, Bakta, Prokka, etc.
├── buildconfig.yaml    # OpenShift BuildConfig and ImageStream
├── deployment.yaml     # Deployment, Service, Route, PVC, ServiceAccount
└── deploy.sh          # One-command deployment script
```

## Prerequisites

- OpenShift cluster with GPU nodes
- Cluster admin access (for privileged SCC)
- Namespace: `hpc-workshopv1` (or modify YAMLs)

## Quick Deploy (One Command)

```bash
./deploy.sh
```

## Manual Deployment Steps

### 1. Grant Privileged SCC (Requires cluster-admin)

```bash
oc adm policy add-scc-to-user privileged -z ansuya-jupyter-dind -n hpc-workshopv1
```

### 2. Create ImageStream and BuildConfig

```bash
oc apply -f buildconfig.yaml
```

### 3. Start the Build

```bash
oc start-build parabricks-jupyter-dind -n hpc-workshopv1 --follow
```

**Build time: 15-30 minutes** (large image with Conda, Parabricks, genomics tools)

### 4. Deploy the Workbench

```bash
oc apply -f deployment.yaml
```

### 5. Verify Deployment

```bash
# Check pod status
oc get pods -n hpc-workshopv1 | grep ansuya

# Get access URL
oc get route ansuya-jupyter-dind -n hpc-workshopv1 -o jsonpath='{.spec.host}'
```

## Access URL

```
https://ansuya-jupyter-dind-hpc-workshopv1.apps.rosa.ukhsa-rosa-eu1.j5jq.p3.openshiftapps.com/lab
```

## Copy Data Files (After Pod is Running)

The workbench starts with empty storage. Copy Ansuya's data files:

```bash
# Get pod name
POD=$(oc get pods -n hpc-workshopv1 -l app=ansuya-jupyter-dind -o jsonpath='{.items[0].metadata.name}')

# Copy data files (from local or another location)
oc cp /path/to/data/ $POD:/opt/app-root/src/ -n hpc-workshopv1
```

**Required data files:**
- `isolate_01_sorted.bam` (3GB)
- `isolate_01_sorted.bam.bai`
- `isolate_01_variants.vcf`
- `Ecoli_K12_MG1655_ref.fasta`
- `Parabricks_Pathogentest.ipynb`

## Resources

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 2 | 4 |
| Memory | 48Gi | 64Gi |
| GPU | 2 | 2 |
| Storage | 100Gi PVC | - |

## Included Tools

### Genomics
- **Parabricks 4.6.0** - GPU-accelerated genomics
- **Bakta** - Bacterial genome annotation
- **Prokka** - Prokaryotic annotation
- **GATK 4.6.1** - Genome Analysis Toolkit
- **samtools 1.19.2** - SAM/BAM manipulation
- **bcftools 1.19** - VCF manipulation
- **bwa 0.7.17** - Burrows-Wheeler Aligner
- **SRA Toolkit 3.2.0** - NCBI data access
- **EDirect** - NCBI E-utilities

### Docker-in-Docker
- Docker CE with NVIDIA Container Toolkit
- Run containerized pipelines inside the workbench
- GPU passthrough to inner containers

### Python
- Python 3.12
- JupyterLab
- BioPython, pysam, pandas, numpy, matplotlib, seaborn

## Troubleshooting

### Pod stuck in Pending (GPU)
```bash
oc describe pod -l app=ansuya-jupyter-dind -n hpc-workshopv1
```
Check for "Insufficient nvidia.com/gpu" - need available GPU nodes.

### Pod stuck in ImagePullBackOff
Build not complete yet. Check build status:
```bash
oc get builds -n hpc-workshopv1 | grep parabricks
oc logs build/parabricks-jupyter-dind-1 -n hpc-workshopv1 --tail=20
```

### Pod in CrashLoopBackOff
Check if privileged SCC was applied:
```bash
oc get pod -l app=ansuya-jupyter-dind -n hpc-workshopv1 -o yaml | grep -A5 securityContext
```

### Docker not starting inside pod
```bash
oc rsh <pod-name> -n hpc-workshopv1
docker info  # Should show Docker daemon running
```

## Namespace Change

To deploy in a different namespace, update these files:
1. `deployment.yaml` - Change all `namespace: hpc-workshopv1` to your namespace
2. `buildconfig.yaml` - Change `namespace: hpc-workshopv1` to your namespace
3. SCC command - Change `-n hpc-workshopv1` to your namespace

## Contact

- **Original Setup**: Dare Oke
- **User**: Anasuya Chatterjee
- **Cluster**: ROSA ukhsa-rosa-eu1
