# Infrastructure Questions for Client

**Context:** These questions focus on deployment infrastructure and are **not covered** by the existing ML-focused questions (Sections A-F).

---

## G. Deployment Infrastructure & DevOps

> 1. **Container Runtime:** What container runtime is currently installed on the Cognition appliances - Docker, containerd, or Podman? Is nvidia-container-toolkit already configured and working?
>
> 2. **Container Registry:** Is there an existing container registry (Harbor, Artifactory, JFrog) for storing images? For air-gapped deployments, how are container images currently distributed to devices?
>
> 3. **Model Storage & Versioning:** How are TensorRT model engines stored and versioned today - model registry, object storage, or files on disk? What's the approximate size per model version?
>
> 4. **GPU Stack Versions:** What NVIDIA driver, CUDA, and TensorRT versions are currently installed on the Jetson Thor and RTX 4000 devices? Are they consistent across devices?
>
> 5. **Existing Automation:** Is there any deployment automation in place today (Ansible, scripts, CI/CD pipeline), or are deployments currently manual?
>
> 6. **Device Access:** How do we access the appliances for deployment and troubleshooting - SSH, remote management console, VPN? What credentials/access do we need?
>
> 7. **Local Storage:** How much local disk space is available on each appliance for models, container images, and vector DB data?
>
> 8. **Fleet Scale:** How many appliances are we targeting for this deployment - rough ballpark? (Affects whether we need fleet management tooling)
>
> 9. **Logging & Monitoring:** Where do application logs and GPU metrics go today - local files, centralized logging system (ELK, Loki), or not yet set up?

---

## H. Target Performance & SLAs

> 10. **Latency Targets:** What are the specific latency goals we're optimizing toward?
>     - Time to First Token (TTFT): _____ ms target?
>     - End-to-end response time: _____ seconds target?
>     - Tokens per second (TPS): _____ target?
>
> 11. **Concurrency Target:** What's the target number of concurrent users per appliance? Is 20 the goal, or should we aim higher/lower?
>
> 12. **Availability/Uptime:** Are there uptime SLAs (e.g., 99.9%)? This determines whether we need Kubernetes/K3s for failover or if Docker Compose is sufficient.

---

## Copy-Paste Ready Message

```
Hi @Nishant - As I start designing the deployment infrastructure, a few questions that will help shape the solution:

**Deployment Infrastructure:**
1. What container runtime is on the appliances today - Docker, containerd, Podman? Is nvidia-container-toolkit configured?

2. Is there an existing container registry? For air-gapped sites, how are images currently distributed?

3. How are TensorRT model engines stored and versioned - registry, object storage, or files on disk? Approximate size per model?

4. What NVIDIA driver, CUDA, and TensorRT versions are installed on Thor and RTX devices?

5. Any existing deployment automation (Ansible, scripts, CI/CD), or is it manual today?

6. How do we access appliances for deployment - SSH, remote console, VPN?

7. How much local disk space is available per appliance?

8. Rough number of appliances we're targeting for deployment?

9. Where do logs go today - local files, centralized logging, or not set up yet?

**Performance Targets:**
10. What are the specific latency targets - TTFT, end-to-end, TPS?

11. Target concurrent users per appliance - is 20 the goal?

12. Any uptime SLAs that require failover/HA design?

These answers will help me design the deployment automation and determine if we need K3s or if Docker Compose is sufficient.
```

---

## Why Each Question Matters

| Question | Impact on Design |
|----------|------------------|
| Container runtime | Deployment scripts differ for Docker vs containerd |
| Registry | Affects CI/CD pipeline and air-gapped distribution |
| Model storage | Volume mounts, storage sizing, rollback strategy |
| GPU stack versions | Container base image compatibility |
| Existing automation | Build on existing or start fresh |
| Device access | Automation approach (SSH, API, etc.) |
| Disk space | Model + image storage planning |
| Fleet scale | 10 devices = manual OK; 100+ = need fleet tools |
| Logging | Monitoring and debugging strategy |
| Latency targets | Success criteria for optimization |
| Concurrency target | Session limits, load testing goals |
| Uptime SLAs | Docker Compose vs K3s decision |
