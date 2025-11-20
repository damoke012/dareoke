# Production Readiness Checklist for Parabricks Workbench

## Security Review

### ✅ Current Good Practices
- [x] Container runs as non-root user (USER 1001)
- [x] Only switches to root temporarily for installations
- [x] Proper file permissions (1001:0 ownership, group writable)
- [x] No hardcoded secrets or credentials
- [x] Uses official Red Hat UBI base image
- [x] Cleans up package manager cache

### ⚠️ Items to Review

#### 1. Parabricks Binary Integration
**Current State**: Using a placeholder bash script for `pbrun`
**Production Needed**:
- [ ] Obtain actual Clara Parabricks binary/installation
- [ ] Copy real Parabricks tools from official NVIDIA image
- [ ] Verify Parabricks license compliance

**Options**:
```dockerfile
# Option A: Copy from NVIDIA image (multi-stage build)
FROM nvcr.io/nvidia/clara/clara-parabricks:4.6.0-1 AS parabricks
FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/jupyter-datascience-cpu-py312-ubi9:2025.1
COPY --from=parabricks /usr/local/parabricks /opt/parabricks

# Option B: Download and install (if license allows)
# Requires NVIDIA NGC API key and proper licensing
```

#### 2. GPU Support
**Current State**: No GPU configuration
**Production Consideration**:
- [ ] Does the workbench need GPU access?
- [ ] If yes, add NVIDIA GPU labels and drivers
- [ ] Configure CUDA libraries
- [ ] Set resource limits for GPU

**If GPU needed**:
```yaml
# Add to workbench pod spec
resources:
  limits:
    nvidia.com/gpu: 1
```

#### 3. Storage and Data Access
- [ ] Define persistent volume claims for genomics data
- [ ] Set up data lake/object storage integration (S3, etc.)
- [ ] Configure appropriate storage class
- [ ] Define data retention policies

#### 4. Version Pinning
- [ ] Pin Python package versions (already done ✓)
- [ ] Document base image version (2025.1 ✓)
- [ ] Create version tags for the workbench image

#### 5. Documentation
- [ ] Add usage documentation for end users
- [ ] Document required input data formats
- [ ] Provide example workflows
- [ ] Add troubleshooting guide

## Dockerfile Best Practices Review

### ✅ Already Implemented
```dockerfile
# Good: Combines RUN commands to reduce layers
RUN dnf install -y wget bzip2 && dnf clean all

# Good: Explicit version pinning
RUN pip install biopython==1.86 pysam==0.23.3

# Good: Proper OpenShift permissions
RUN chown -R 1001:0 /opt/app-root/src && chmod -R g+w /opt/app-root/src

# Good: Metadata labels
LABEL maintainer="platform-team"
LABEL description="..."

# Good: Minimal USER 0 scope
USER 0
RUN dnf install ...
USER 1001
```

### 🔄 Potential Improvements

#### 1. Multi-stage Build (if using real Parabricks)
```dockerfile
# Stage 1: Get Parabricks
FROM nvcr.io/nvidia/clara/clara-parabricks:4.6.0-1 AS parabricks

# Stage 2: Build final image
FROM image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/jupyter-datascience-cpu-py312-ubi9:2025.1
COPY --from=parabricks /usr/local/parabricks /opt/parabricks
```

#### 2. Health Checks
```dockerfile
# Add health check for Jupyter
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:8888/ || exit 1
```

#### 3. Build Arguments for Flexibility
```dockerfile
ARG PARABRICKS_VERSION=4.6.0-1
ARG PYTHON_VERSION=3.12
LABEL parabricks.version="${PARABRICKS_VERSION}"
```

## Security Hardening

### Current Security Posture: ✅ Good
- Non-root execution
- Read-only root filesystem compatible
- No privileged escalation
- Minimal attack surface

### Additional Hardening (Optional)
```dockerfile
# Remove unnecessary packages
RUN dnf remove -y wget bzip2 || true

# Set stricter permissions
RUN chmod 750 /opt/parabricks

# Add security labels
LABEL security.scan="passed" \
      security.last-scan-date="2025-11-14"
```

## Testing Checklist

- [ ] Build completes successfully
- [ ] Image size is reasonable (< 5GB recommended)
- [ ] All Python packages import correctly
- [ ] Sample notebook runs without errors
- [ ] Workbench starts in RHOAI
- [ ] File permissions work with arbitrary UIDs
- [ ] No security vulnerabilities in image scan

## Deployment Checklist

### Before Making Global
- [ ] Test in dedicated namespace first
- [ ] Verify with multiple users
- [ ] Check resource consumption (CPU/memory)
- [ ] Validate with sample genomics data
- [ ] Get approval from security team
- [ ] Document support procedures

### Global Deployment
- [ ] Apply global ImageStream (admin task)
- [ ] Update RHOAI dashboard
- [ ] Notify users of new image availability
- [ ] Provide training/documentation
- [ ] Monitor initial usage

## Current State Summary

### What Works Now
✅ Jupyter notebook environment
✅ Python 3.12 with genomics libraries
✅ BioPython, PySam, Pandas, Matplotlib, Seaborn
✅ OpenShift security compliance
✅ Non-root execution
✅ Proper file permissions

### What Needs Work for Production
⚠️ Real Parabricks binary integration (currently placeholder)
⚠️ GPU support (if required)
⚠️ License compliance verification
⚠️ Production data access configuration
⚠️ Comprehensive testing with real genomics workloads

## Recommended Next Steps

1. **Immediate** (for demo/testing):
   - Current setup is fine for demonstration
   - Users can test Python genomics libraries
   - Placeholder pbrun shows what will be available

2. **Before Production** (required):
   - Integrate actual Parabricks binaries
   - Verify NVIDIA licensing compliance
   - Add GPU support if needed
   - Complete security scanning
   - Load test with real data

3. **Future Enhancements**:
   - Add more genomics tools (samtools, bcftools, GATK)
   - Integration with genomics databases
   - Automated pipeline templates
   - Resource optimization

## Risk Assessment

**Current Risk Level**: 🟡 Medium (Safe for testing, not production-ready)

**Risks**:
- Placeholder Parabricks binary won't run real analyses
- No GPU acceleration (slower performance)
- Licensing compliance not verified

**Mitigations**:
- Clearly document current limitations
- Set expectations with users
- Plan for production integration
- Get admin support for global deployment

## Contact for Questions
Platform Team / Dare.Oke@ext.quantiphi.com
