# CI/CD Pipeline Documentation

## Overview

The Forge Cognition CI/CD pipeline supports:
- **Multi-architecture builds** (ARM64 for Jetson Thor, x86 for RTX 4000)
- **Air-gapped deployment** via portable bundles
- **Lab validation** before production release
- **GitOps workflow** with GitHub Actions

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CI/CD FLOW                                      │
│                                                                              │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐ │
│   │   DEV    │───▶│   CI     │───▶│  STAGING │───▶│     PRODUCTION       │ │
│   │          │    │          │    │   (Lab)  │    │    (Air-gapped)      │ │
│   └──────────┘    └──────────┘    └──────────┘    └──────────────────────┘ │
│                                                                              │
│   Git push        Lint/Test       Deploy to       Create bundle            │
│   PR review       Build image     Tesla P40       Transfer via USB         │
│                   Multi-arch      Smoke tests     Deploy to fleet          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
honeywell-forge-lab/
├── cicd/
│   ├── workflows/
│   │   └── build-and-test.yaml    # GitHub Actions workflow
│   ├── scripts/
│   │   ├── load-images.sh         # Load images into Docker (air-gapped)
│   │   ├── deploy-airgapped.sh    # Deploy to edge appliance
│   │   └── create-bundle.sh       # Create portable bundle
│   └── bundles/                   # Generated bundles (gitignored)
├── deployment/
│   ├── docker-compose.yaml        # Main compose file
│   ├── docker-compose.jetson.yaml # Jetson Thor overrides
│   └── docker-compose.rtx.yaml    # RTX 4000 overrides
├── inference-server/
│   ├── Dockerfile                 # Multi-arch Dockerfile
│   ├── server.py                  # Main server code
│   ├── config.yaml                # Base config
│   └── sku_profiles.yaml          # Hardware profiles
└── Makefile                       # Build automation
```

## Workflows

### 1. Development Workflow

```bash
# Make changes to code
vim inference-server/server.py

# Test locally
make test
make dev

# Build for current platform
make build

# Test with Docker
make dev-docker
```

### 2. CI Pipeline (GitHub Actions)

**Trigger:** Push to main/master or PR

**Jobs:**
1. **lint-and-test** - Python linting, YAML validation
2. **build-multiarch** - Build ARM64 + x86 images
3. **test-x86** - Validate x86 image
4. **deploy-lab** - Deploy to self-hosted runner (optional)
5. **create-bundle** - Create air-gapped bundle (manual trigger)

### 3. Air-Gapped Deployment

```bash
# On build machine (with internet)
make bundle VERSION=v1.0.0

# Transfer bundle to appliance
scp forge-cognition-bundle-v1.0.0.tar.gz user@appliance:/tmp/

# On appliance (air-gapped)
tar -xzf forge-cognition-bundle-v1.0.0.tar.gz
cd bundle
./scripts/load-images.sh
./scripts/deploy-airgapped.sh
```

## Build Targets

| Command | Description |
|---------|-------------|
| `make build` | Build for current platform |
| `make build-x86` | Build x86_64 image (RTX 4000) |
| `make build-arm64` | Build ARM64 image (Jetson Thor) |
| `make build-multiarch` | Build and push multi-arch image |
| `make test` | Run all tests |
| `make deploy-lab` | Deploy to lab environment |
| `make bundle` | Create air-gapped bundle |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | `ghcr.io` | Container registry |
| `IMAGE_NAME` | `forge/inference-server` | Image name |
| `VERSION` | `latest` or git tag | Image version |
| `FORGE_SKU` | auto-detect | Force specific SKU |

## Deployment Scenarios

### Scenario 1: Lab Testing (Connected)

```bash
# Deploy to lab with Tesla P40
cd deployment
FORGE_SKU=tesla_p40 docker-compose up -d

# Check status
curl http://localhost:8000/health
curl http://localhost:8000/v1/sku
```

### Scenario 2: Production (Air-Gapped)

```bash
# 1. Create bundle on build machine
make bundle VERSION=v1.0.0

# 2. Transfer to appliance (USB, SCP, etc.)
# File: forge-cognition-bundle-v1.0.0.tar.gz (~2GB)

# 3. On appliance
tar -xzf forge-cognition-bundle-v1.0.0.tar.gz
cd bundle
./scripts/load-images.sh         # Loads correct arch automatically
./scripts/deploy-airgapped.sh    # Deploys with SKU detection
```

### Scenario 3: Fleet Deployment

For deploying to multiple appliances:

```bash
# 1. Create bundle once
make bundle VERSION=v1.0.0

# 2. Copy to fleet management system or USB drives

# 3. On each appliance (can be scripted)
./scripts/load-images.sh
./scripts/deploy-airgapped.sh --sku jetson_thor  # or rtx_4000_pro
```

## Bundle Contents

A bundle contains everything needed for air-gapped deployment:

```
forge-cognition-bundle-v1.0.0.tar.gz
└── bundle/
    ├── images/
    │   ├── forge-inference-x86.tar.gz     # ~1.5GB
    │   └── forge-inference-arm64.tar.gz   # ~1.5GB
    ├── configs/
    │   ├── docker-compose.yaml
    │   ├── sku_profiles.yaml
    │   └── config.yaml
    ├── scripts/
    │   ├── load-images.sh
    │   └── deploy-airgapped.sh
    ├── docs/
    │   └── PERFORMANCE_TUNING.md
    ├── MANIFEST.md
    └── README.txt
```

## Self-Hosted Runner (Optional)

For automated lab deployments, set up a self-hosted GitHub runner:

```bash
# On lab machine with GPU
mkdir actions-runner && cd actions-runner
curl -o actions-runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/YOUR_ORG/YOUR_REPO --token YOUR_TOKEN --labels gpu,self-hosted
./run.sh
```

The workflow will automatically deploy to this runner when pushing to main.

## Versioning Strategy

```
v1.0.0          # Major release
v1.0.1          # Bug fix
v1.1.0          # New feature
v1.1.0-rc1      # Release candidate
latest          # Latest stable
main            # Latest from main branch
sha-abc123      # Specific commit
```

## Troubleshooting

### Build fails on ARM64

```bash
# Ensure QEMU is installed for cross-compilation
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

### Image won't load on appliance

```bash
# Check disk space
df -h

# Check Docker status
systemctl status docker

# Manual load
gunzip -c forge-inference-arm64.tar.gz | docker load
```

### SKU not detected

```bash
# Force SKU manually
FORGE_SKU=jetson_thor ./scripts/deploy-airgapped.sh
# OR
./scripts/deploy-airgapped.sh --sku jetson_thor
```

### Health check fails

```bash
# Check container logs
docker logs forge-inference

# Check GPU access
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

## Integration with Honeywell

When integrating with Honeywell's infrastructure:

1. **Registry:** Change `REGISTRY` to `harbor.honeywell.com/forge`
2. **CI/CD:** Can migrate to Azure DevOps or Jenkins if preferred
3. **Fleet Management:** Can integrate with Ansible/Salt for large fleets
4. **Monitoring:** Can push metrics to Honeywell's Prometheus/Grafana

```yaml
# Example for Honeywell registry
env:
  REGISTRY: harbor.honeywell.com
  IMAGE_NAME: forge/inference-server
```
