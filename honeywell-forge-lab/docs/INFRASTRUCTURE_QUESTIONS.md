# Infrastructure Questions for Client

**Context:** These questions focus on deployment infrastructure and are **not covered** by the existing ML-focused questions (Sections A-F).

**Updated:** Dec 9, 2024 - Based on kickoff presentation dependencies.

---

## Dependencies from Honeywell (Per Kickoff Slides)

The following items were listed as **Honeywell dependencies** - these are blocking items we need:

1. ☐ Forge Cognition hardware devices (Blackwell RTX Pro 4000 and Jetson Thor) with required firmware, OS image, and base runtime pre-configured
2. ☐ Access to development units (physical or remote) for optimization, testing, validation
3. ☐ Complete hardware specs: GPU config, RAM, storage, networking parameters, thermal limits
4. ☐ Access to Forge Cognition unified software environment and all required runtime components
5. ☐ Access to container registry, internal package repos, and build artifacts
6. ☐ Existing application access for Maintenance Assist with all relevant API documentation
7. ☐ Workflows and domain knowledge documentation
8. ☐ Sample datasets, ground-truth data, historical logs, test inputs for benchmarking
9. ☐ Credentials for dev environments, registries, monitoring tools, test labs, Git repos
10. ☐ VPN or secure remote access to Forge Cognition devices and testing environments
11. ☐ Designated point of contact for technical and functional decisions
12. ☐ Weekly SME availability for requirement clarifications and reviews
13. ☐ Approval workflow management for environment access, device usage, testing windows, security reviews

---

## G. Deployment Infrastructure & DevOps

1. **Container Runtime:** What container runtime is on the appliances today - Docker, containerd, or Podman?
2. **Container Registry:** Is there an existing container registry (Harbor, Artifactory, JFrog)? For air-gapped sites, how are container images currently distributed to devices?
3. **Model Storage & Versioning:** How are TensorRT model engines stored and versioned today - model registry, object storage, or files on disk? What's the approximate size per model version?
4. **GPU Stack Versions:** What NVIDIA driver, CUDA, and TensorRT versions are currently installed on each SKU (Jetson Thor / RTX 4000)?
5. **Existing Automation:** Is there any deployment automation in place today (Ansible, scripts, CI/CD), or are deployments manual?
6. **Device Access:** How do we access appliances for deployment and troubleshooting - SSH, remote management console, VPN?
7. **Local Storage:** How much local disk space is available on each appliance for models and container images?
8. **Fleet Scale:** How many appliances are we targeting for this deployment - ballpark number?
9. **Logging & Monitoring:** Where do application and GPU logs go today - local files, centralized logging (ELK, Loki), or not yet set up?
10. **Operating System:** What OS will be running on the appliances - Ubuntu, L4T, or something else?

---

## H. Target Performance & SLAs

11. **Latency Targets:** What are the specific latency goals - TTFT (ms), end-to-end response time (s), tokens per second?
12. **Concurrency Target:** What's the target number of concurrent users per appliance - is 20 the goal, or should we aim higher/lower?
13. **Availability/Uptime:** Are there uptime SLAs (e.g., 99.9%)? This determines whether we need K3s for failover or if Docker Compose is sufficient.

---

## I. Container Orchestration & Microservices

14. **Orchestration Decision:** Has a decision been made on container orchestration - K3s, plain Docker Compose, or another approach? What's driving that decision?
15. **Microservice Inventory:** How many microservices/containers need to run on each appliance? (LLM, embeddings, reranker, Milvus, guardrails, API gateway, etc.)

---

## J. GPU Partitioning & Resource Isolation

16. **GPU Sharing Strategy:** Is GPU partitioning being considered (MIG, time-slicing, or CUDA MPS) to isolate workloads, or will services share the GPU without isolation?
17. **Milvus GPU Requirement:** Does Milvus need GPU acceleration for vector search, or can it run CPU-only to free GPU resources for the LLM?
18. **Resource Contention Handling:** When GPU memory pressure occurs, what's the expected behavior - queue requests, reject new sessions, or degrade gracefully?

---

## K. Jetson-Specific

19. **JetPack Version:** What JetPack version is installed on the Jetson Thor devices? (This determines CUDA, TensorRT, and container base image compatibility)
20. **Tegra Verification:** Has the target TensorRT-LLM version been verified to work on Tegra/L4T, or is that part of our testing scope?

---

## L. CI/CD & Production Deployment (Critical for alignment)

21. **Current CI/CD Platform:** What CI/CD platform is used today - Jenkins, GitHub Actions, GitLab CI, Azure DevOps, or something else?
22. **Build Pipeline:** How are container images built today - locally, in CI/CD, or both? What triggers a build (commit, tag, manual)?
23. **Testing in Pipeline:** What tests run in CI/CD today - unit tests, integration tests, model validation, GPU tests?
24. **Deployment Method:** How are updates deployed to edge appliances today - manual push, pull-based (ArgoCD/Flux), or scripts?
25. **Rollback Strategy:** How do you rollback a bad deployment - previous container version, config revert, or full reinstall?
26. **Secrets Management:** How are API keys, credentials, and model access tokens managed - environment variables, Vault, K8s secrets?

---

## M. Current Inference Stack (Critical for optimization)

27. **Inference Backend Today:** What runs the LLM today - raw HuggingFace Transformers, vLLM, TensorRT-LLM, Triton, or something else?
28. **Model Format:** What format is the model in - HuggingFace checkpoint, ONNX, TensorRT engine, or other?
29. **Model Loading:** How is the model loaded - downloaded at startup, baked into container, or mounted from volume?
30. **API Structure:** Does the current API follow OpenAI-compatible format, or is it custom? Can you share the API spec/Swagger?
31. **Batching Today:** Is request batching enabled today? If so, what batch sizes are used?
32. **Streaming:** Is token streaming used for responses, or batch completion only?

---

## Copy-Paste Ready Message

```
Hi @Nishant - As I start designing the deployment infrastructure, a few questions that will help shape the solution:

**Deployment Infrastructure:**
1. What container runtime is on the appliances today - Docker, containerd, or Podman?
2. Is there an existing container registry? For air-gapped sites, how are images currently distributed?
3. How are TensorRT model engines stored and versioned - registry, object storage, or files on disk? Approximate size per model?
4. What NVIDIA driver, CUDA, and TensorRT versions are installed on each SKU (Thor / RTX)?
5. Any existing deployment automation (Ansible, scripts, CI/CD), or is it manual today?
6. How do we access appliances for deployment - SSH, remote console, VPN?
7. How much local disk space is available per appliance?
8. Ballpark number of appliances we're targeting?
9. Where do logs go today - local files, centralized logging, or not set up yet?
10. What OS will be running - Ubuntu, L4T, or something else?

**Performance Targets:**
11. What are the specific latency targets - TTFT, end-to-end, TPS?
12. Target concurrent users per appliance - is 20 the goal?
13. Any uptime SLAs that require failover/HA design?

**Orchestration & Microservices:**
14. Has a decision been made on orchestration - K3s, Docker Compose, or another approach?
15. How many microservices/containers run on each appliance? (LLM, embeddings, reranker, Milvus, guardrails, etc.)

**GPU Partitioning:**
16. Is GPU partitioning being considered (MIG, time-slicing, CUDA MPS) to isolate workloads?
17. Does Milvus need GPU acceleration, or can it run CPU-only to free resources for the LLM?
18. When GPU memory pressure occurs, what's the expected behavior - queue, reject, or degrade?

**Jetson-Specific:**
19. What JetPack version is on the Thor devices?
20. Has TensorRT-LLM been verified on Tegra/L4T, or is that our testing scope?

**CI/CD & Production (Critical for alignment):**
21. What CI/CD platform is used today - Jenkins, GitHub Actions, GitLab, Azure DevOps?
22. How are container images built - locally, in CI/CD, or both? What triggers a build?
23. What tests run in CI/CD - unit tests, integration tests, GPU tests?
24. How are updates deployed to appliances - push, pull-based (ArgoCD), or scripts?
25. How do you rollback a bad deployment?
26. How are secrets/credentials managed?

**Current Inference Stack (Critical for optimization):**
27. What runs the LLM today - HuggingFace, vLLM, TensorRT-LLM, Triton?
28. What format is the model in - HuggingFace checkpoint, ONNX, TensorRT engine?
29. How is the model loaded - downloaded at startup, baked into container, or mounted?
30. Does the API follow OpenAI format, or custom? Can you share the spec?
31. Is request batching enabled? What batch sizes?
32. Is token streaming used, or batch completion only?

These answers will help me design the deployment automation and align with your existing practices.
```

---

## Why Each Question Matters

| Question | Impact on Design |
|----------|------------------|
| Container runtime | Deployment scripts differ for Docker vs containerd vs Podman |
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
| Orchestration decision | K3s adds complexity but enables HA; Docker Compose is simpler |
| Microservice count | Resource allocation, scheduling complexity |
| GPU partitioning | MIG requires Ampere+; time-slicing has overhead |
| Milvus GPU | Offloading to CPU frees ~5-10GB for LLM |
| Resource contention | Determines graceful degradation strategy |
| JetPack version | Must match container base image (L4T) |
| Tegra verification | Avoids deployment surprises on ARM64 |
