# Developer Setup Guide

Guide for setting up a shared repository where all developers can create their own test environments.

## Recommended Repository Structure

```
honeywell-forge-cognition/          # Main repo (suggested name)
├── main                            # Protected - production-ready code
├── develop                         # Integration branch
├── feature/*                       # Feature branches
├── test/developer-name/*           # Personal test branches
└── release/*                       # Release candidates
```

## Setting Up the Shared Repository

### Option 1: GitHub (Recommended)

```bash
# 1. Create new repo on GitHub
# Go to github.com/[org] → New Repository
# Name: honeywell-forge-cognition
# Private repo (recommended for client work)

# 2. Clone and set up
git clone https://github.com/[org]/honeywell-forge-cognition.git
cd honeywell-forge-cognition

# 3. Copy prototype code
cp -r /path/to/honeywell-forge-lab/* .

# 4. Initial commit
git add .
git commit -m "Initial prototype setup"
git push origin main

# 5. Create develop branch
git checkout -b develop
git push -u origin develop
```

### Option 2: GitLab

```bash
# Similar process, use GitLab URL
git clone https://gitlab.com/[org]/honeywell-forge-cognition.git
```

### Option 3: Azure DevOps

```bash
# Use Azure Repos URL
git clone https://dev.azure.com/[org]/[project]/_git/honeywell-forge-cognition
```

## Branch Protection Rules

Set these on GitHub/GitLab to prevent accidents:

### `main` branch:
- ✅ Require pull request reviews (1-2 approvers)
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Include administrators
- ❌ Allow force pushes

### `develop` branch:
- ✅ Require pull request reviews (1 approver)
- ✅ Require status checks to pass
- ❌ Include administrators (allow direct push for leads)

### `test/*` branches:
- No protection (developers can push freely)

## Developer Workflow

### 1. Clone the Repo
```bash
git clone https://github.com/[org]/honeywell-forge-cognition.git
cd honeywell-forge-cognition
```

### 2. Create Your Test Branch
```bash
# Create personal test branch
git checkout -b test/dario/gpu-optimization
git push -u origin test/dario/gpu-optimization

# Or for a specific feature test
git checkout -b test/dario/tensorrt-fp8-testing
```

### 3. Work on Your Branch
```bash
# Make changes
vim inference-server/server.py

# Commit frequently
git add .
git commit -m "Test FP8 quantization settings"

# Push to your branch
git push
```

### 4. Test in Your Environment
```bash
# Deploy to your test environment (K3s or Docker)
./k3s-deployment/scripts/deploy-forge.sh

# Or with Docker Compose
docker-compose -f deployment/docker-compose.yaml up -d
```

### 5. Share Results / Create PR
```bash
# If test is successful, create PR to develop
# Go to GitHub → Pull Requests → New PR
# base: develop ← compare: test/dario/gpu-optimization
```

## Recommended Branch Naming

| Pattern | Use Case | Example |
|---------|----------|---------|
| `test/[name]/*` | Personal testing | `test/dario/latency-tuning` |
| `feature/[ticket]` | New features | `feature/FORGE-123-session-mgmt` |
| `bugfix/[ticket]` | Bug fixes | `bugfix/FORGE-456-memory-leak` |
| `experiment/[name]` | R&D experiments | `experiment/mig-partitioning` |
| `release/[version]` | Release prep | `release/1.0.0` |

## CI/CD Pipeline Per Branch

Add to `.github/workflows/ci.yaml`:

```yaml
name: CI Pipeline

on:
  push:
    branches:
      - main
      - develop
      - 'test/**'
      - 'feature/**'
  pull_request:
    branches:
      - main
      - develop

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest flake8

      - name: Lint
        run: flake8 inference-server/

      - name: Unit tests
        run: pytest tests/ -v

  build-container:
    runs-on: ubuntu-latest
    needs: lint-and-test
    steps:
      - uses: actions/checkout@v4

      - name: Build container
        run: |
          docker build -t forge-inference:${{ github.sha }} \
            -f inference-server/Dockerfile \
            inference-server/

      # Only push to registry for main/develop
      - name: Push to registry
        if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/develop'
        run: |
          echo "Would push to registry here"

  # GPU tests only run on specific branches (requires self-hosted runner)
  gpu-tests:
    runs-on: [self-hosted, gpu]
    if: startsWith(github.ref, 'refs/heads/test/') || github.ref == 'refs/heads/develop'
    needs: build-container
    steps:
      - uses: actions/checkout@v4

      - name: Run GPU tests
        run: |
          ./scripts/run-gpu-tests.sh
```

## Environment Per Developer

Each developer can have their own test environment:

### Option A: Shared Lab Machine with Namespaces (K3s)
```bash
# Each developer gets their own K8s namespace
kubectl create namespace test-dario
kubectl create namespace test-john
kubectl create namespace test-sarah

# Deploy to your namespace
kubectl apply -f k3s-deployment/manifests/ -n test-dario
```

### Option B: Separate VMs/Containers
```bash
# Each developer gets their own Docker context
docker context create dario-test --docker "host=ssh://dario@lab-machine"
docker context use dario-test

# Deploy
docker-compose up -d
```

### Option C: Cloud Dev Environments (GitHub Codespaces / GitPod)
```yaml
# .devcontainer/devcontainer.json
{
  "name": "Forge Cognition Dev",
  "image": "mcr.microsoft.com/devcontainers/python:3.11",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  },
  "postCreateCommand": "pip install -r requirements.txt"
}
```

## Suggested Repository Setup Steps

### For Honeywell/Quantiphi Team:

1. **Create the repo** (one person):
   ```bash
   # Create on GitHub/GitLab/Azure DevOps
   # Name: honeywell-forge-cognition (or their preferred name)
   ```

2. **Add team members** with appropriate access:
   - Admins: Tech leads
   - Write: Developers
   - Read: Stakeholders

3. **Import prototype code**:
   ```bash
   git clone [new-repo-url]
   cd honeywell-forge-cognition

   # Copy from prototype
   cp -r /path/to/honeywell-forge-lab/* .

   git add .
   git commit -m "Import prototype from Quantiphi"
   git push
   ```

4. **Set up branch protection** (see above)

5. **Each developer creates their test branch**:
   ```bash
   git checkout -b test/[your-name]/initial-setup
   git push -u origin test/[your-name]/initial-setup
   ```

## Questions to Ask Client

Add these to the infrastructure questions:

1. **Source Control:** What Git platform do you use - GitHub, GitLab, Azure DevOps, Bitbucket?
2. **Access:** Can we get write access to create a shared repo, or should we work in your existing repo?
3. **CI/CD Integration:** Should the repo connect to your existing CI/CD pipelines?
4. **Naming Convention:** Any required naming patterns for repos/branches?
5. **Code Review:** What's your PR review process - 1 approver, 2 approvers, specific reviewers?

## Quick Reference Card

```
# Clone repo
git clone https://github.com/[org]/honeywell-forge-cognition.git

# Create your test branch
git checkout -b test/YOUR_NAME/description

# Push your branch
git push -u origin test/YOUR_NAME/description

# Deploy to test
./k3s-deployment/scripts/deploy-forge.sh

# Create PR when ready
# GitHub → Pull Requests → New PR → base:develop
```
