# NVIDIA Clara Parabricks - OpenShift Container

Containerized NVIDIA Clara Parabricks 4.6.0-1 for OpenShift and OpenShift AI Workbench.

## Overview

Dockerfile and deployment manifests for running NVIDIA Clara Parabricks genomics analysis tools in OpenShift.

**Base Image**: `nvcr.io/nvidia/clara/clara-parabricks:4.6.0-1`
**Parabricks Version**: 4.6.0-1
**OpenShift Compatible**: Yes (runs as user 1001)

## Quick Start

### Build Image

```bash
podman build -t clara-parabricks:4.6.0-1 -f Dockerfile .
```

### Push to Registry

```bash
# Tag for your registry
podman tag clara-parabricks:4.6.0-1 <your-registry>/clara-parabricks:latest

# Push
podman push <your-registry>/clara-parabricks:latest
```

### Deploy to OpenShift

```bash
# Create namespace
oc new-project parabricks

# Apply manifests
oc apply -f imagestream.yaml
oc apply -f buildconfig.yaml

# Start build
oc start-build clara-parabricks-build --follow
```

## Using in OpenShift AI Workbench

1. Access OpenShift AI Dashboard
2. Create or select Data Science Project
3. Click "Create workbench"
4. Select **Custom Image**
5. Enter your image URL
6. Configure GPU (optional)
7. Launch workbench

### In JupyterLab

```bash
# Terminal
pbrun version
pbrun --help

# Run analysis
pbrun germline \
    --ref /data/reference.fasta \
    --in-fq /data/sample_R1.fq.gz /data/sample_R2.fq.gz \
    --out-bam /output/sample.bam \
    --out-variants /output/variants.vcf
```

## Available Tools

### Pipelines
- `germline` - Germline variant calling
- `somatic` - Somatic variant calling
- `deepvariant_germline` - Deep learning germline calling
- `pacbio_germline` - PacBio long-read pipeline
- `ont_germline` - Oxford Nanopore pipeline

### Tools
- `fq2bam` - FASTQ to BAM alignment
- `haplotypecaller` - Variant calling
- `mutectcaller` - Somatic variant calling
- `deepvariant` - Deep learning caller
- `bamsort` - Sort BAM files
- `markdup` - Mark duplicates
- `bqsr` - Base quality recalibration
- And 20+ more

## Files

| File | Description |
|------|-------------|
| `Dockerfile` | Container image definition |
| `imagestream.yaml` | OpenShift ImageStream |
| `buildconfig.yaml` | OpenShift BuildConfig |

## Example Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: genomics-analysis
spec:
  template:
    spec:
      containers:
      - name: parabricks
        image: <your-registry>/clara-parabricks:latest
        command: ["pbrun", "germline"]
        args:
        - "--ref"
        - "/data/reference.fasta"
        - "--in-fq"
        - "/data/sample_R1.fq.gz"
        - "/data/sample_R2.fq.gz"
        - "--out-bam"
        - "/output/sample.bam"
        - "--out-variants"
        - "/output/variants.vcf"
        resources:
          limits:
            nvidia.com/gpu: "1"
      restartPolicy: Never
```

## Requirements

- OpenShift 4.10+
- (Optional) NVIDIA GPU nodes

**Recommended Resources**:
- CPU: 16+ cores
- Memory: 32+ GB
- GPU: 1+ NVIDIA GPU

## Testing

```bash
# Run test job
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: test-parabricks
spec:
  template:
    spec:
      containers:
      - name: test
        image: <your-registry>/clara-parabricks:latest
        command: ["pbrun", "version"]
      restartPolicy: Never
EOF

# Check logs
oc logs -f job/test-parabricks
```

## Documentation

- Parabricks: https://docs.nvidia.com/clara/#parabricks
- OpenShift: https://docs.openshift.com/

## License

NVIDIA Clara Parabricks - see NVIDIA licensing terms
