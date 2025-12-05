# Honeywell Forge Cognition - Discovery Meeting Questions

## Meeting Date: [Tomorrow's Date]
## Purpose: Initial Discovery & Requirements Workshop

---

## 1. Hardware & Environment Questions

### Forge Cognition Device Access
- [ ] Will we have **physical access** to the Forge Cognition devices, or will all work be done **remotely**?
- [ ] How many development units are available for the project team?
- [ ] Is there a **dedicated test environment**, or will we share devices with other teams?
- [ ] What is the **lead time** for getting VPN/remote access provisioned?

### Hardware Specifications
- [ ] Can you share the **exact GPU model** for the RTX Pro 4000 variant? (RTX Pro 4000 Ada? Blackwell?)
- [ ] What is the **total system RAM** available on each SKU (RTX Pro vs Thor)?
- [ ] What is the **storage capacity and type** (NVMe? eMMC?) on the Forge Cognition devices?
- [ ] Are there any **thermal throttling thresholds** documented that we should design around?
- [ ] For Jetson Thor: Is **NVLink** enabled between chiplets, and what bandwidth is available?

### Software Stack
- [ ] What **OS and kernel version** is running on the devices?
- [ ] Is the base image **Jetpack-based** for Thor? What version?
- [ ] What **container runtime** is pre-installed? (Docker, containerd, cri-o?)
- [ ] Is there an existing **orchestration layer**? (Kubernetes, k3s, custom?)
- [ ] What **CUDA and cuDNN versions** are installed?

---

## 2. Application & Model Questions

### Maintenance Assist (Phase 0)
- [ ] What is the **current architecture** of the Maintenance Assist application?
- [ ] What **model(s)** are being used? (Name, size, framework - PyTorch/ONNX/etc.)
- [ ] What is the **current inference latency** baseline?
- [ ] What are the **input/output specifications**? (Token limits, response format)
- [ ] Is this a **batch processing** or **real-time interactive** workload?

### AI Assisted Asset Engineering (Phase 1)
- [ ] What makes this different from Maintenance Assist technically?
- [ ] Does "conversational assistance" mean **multi-turn conversations**?
- [ ] What is the expected **context window size** for conversations?
- [ ] Are there **guardrails or safety filters** that need to be preserved during optimization?

### Model Details
- [ ] Are the models **proprietary Honeywell models** or based on **open-source foundations**?
- [ ] What **framework** were the models trained in? (PyTorch, TensorFlow, JAX)
- [ ] Are the models already in **ONNX or TensorRT format**, or are they still in native format?
- [ ] What is the **current precision** of the models? (FP32, FP16, INT8)
- [ ] Have any **quantization attempts** been made already?

---

## 3. Performance & KPI Questions

### Target Metrics
- [ ] What are the **target latency requirements** for TTFT (Time to First Token)?
  - P50: ___ms
  - P90: ___ms
  - P99: ___ms
- [ ] What is the **target throughput** (tokens/second)?
- [ ] What is the **target number of concurrent sessions**?
- [ ] Is there a **maximum acceptable latency degradation** under peak load?

### Baseline Measurements
- [ ] Do you have **existing benchmarks** for the current deployment?
- [ ] What tools/methods were used for baseline measurements?
- [ ] Is there a **performance regression threshold** that would block deployment?

### Hardware Utilization Targets
- [ ] What is the **acceptable GPU utilization** range? (e.g., 70-90%)
- [ ] What is the **maximum memory footprint** allowed per session?
- [ ] Are there **power consumption constraints** we need to meet?

---

## 4. Deployment & Operations Questions

### Deployment Environment
- [ ] Will deployments be to a **single device** or **fleet of devices**?
- [ ] Is there an existing **CI/CD pipeline** we should integrate with?
- [ ] What **container registry** should we push to?
- [ ] Is there a **GitOps workflow** in place?

### Runtime Environment
- [ ] What **inference server** is currently used? (Triton, TGI, vLLM, custom?)
- [ ] How are **models currently loaded**? (From local storage, NFS, object storage?)
- [ ] What **logging/monitoring** infrastructure exists?
- [ ] Is there **Prometheus/Grafana** or similar observability stack?

### Security & Compliance
- [ ] Are there **specific security requirements** for the container images?
- [ ] Do images need to be **scanned and signed**?
- [ ] Are there **network isolation requirements** for the inference service?
- [ ] What **secrets management** solution is used?

---

## 5. Testing & Validation Questions

### Test Data
- [ ] What **test datasets** will be provided for benchmarking?
- [ ] Is there **ground truth data** for accuracy validation?
- [ ] Are there **production traffic patterns** we can simulate?
- [ ] What is the **data sensitivity level**? Can we use it in all environments?

### Acceptance Criteria
- [ ] What are the **specific acceptance criteria** for each deliverable?
- [ ] Who will **sign off** on testing and validation reports?
- [ ] Is there a **staging environment** for UAT before production?

### Failover & Recovery
- [ ] What is the **RTO (Recovery Time Objective)** for the inference service?
- [ ] What **failure scenarios** should we design recovery for?
- [ ] Is there **redundancy** built into the hardware design?

---

## 6. Integration Questions

### Forge Core Integration
- [ ] How does the AI inference service **integrate with Forge Core**?
- [ ] What **APIs** does Forge Core expose for AI services to consume?
- [ ] Are there **message queues or event streams** for async processing?

### EBI & Niagara Integration
- [ ] How will **Maintenance Assist** interact with EBI/Niagara systems?
- [ ] What **data flows** need to happen between systems?
- [ ] Are there **real-time constraints** on these integrations?

---

## 7. Team & Communication Questions

### Honeywell Team
- [ ] Who is the **primary technical contact** for daily questions?
- [ ] Who is the **domain expert** for Maintenance Assist?
- [ ] Who is the **domain expert** for Asset Engineering?
- [ ] What is the **escalation path** for blockers?

### Working Model
- [ ] What **time zones** is the Honeywell team working in?
- [ ] What is the preferred **communication channel**? (Slack, Teams, email)
- [ ] What is the **meeting cadence** for status updates?
- [ ] How should we **document and share findings**?

### Access & Credentials
- [ ] When will **environment access** be provisioned?
- [ ] What is the **process for requesting additional access**?
- [ ] Is there a **dedicated sandbox** we can experiment in?

---

## 8. Risk & Dependency Questions

### Critical Dependencies
- [ ] What are the **biggest risks** Honeywell sees for this project?
- [ ] Are there any **known hardware issues** or firmware limitations?
- [ ] What is the **availability of Honeywell SMEs** during the project?
- [ ] Are there any **competing priorities** that might affect resource availability?

### Technical Risks
- [ ] Has **TensorRT-LLM compatibility** been validated with the current models?
- [ ] Are there any **model layers or operations** known to be problematic?
- [ ] What happens if the **target performance cannot be achieved**?

### Timeline Risks
- [ ] Are there any **hard deadlines** driving the timeline?
- [ ] What is the **buffer** if a sprint deliverable slips?
- [ ] Are there **external dependencies** (other teams, vendors) we should know about?

---

## 9. Out of Scope Clarifications

- [ ] Confirm: We are **not responsible** for model retraining or fine-tuning on new data?
- [ ] Confirm: We are **not responsible** for application UI/UX development?
- [ ] Confirm: Hardware procurement and **firmware updates** are Honeywell's responsibility?
- [ ] What happens if optimization requires **architectural changes to the application**?

---

## 10. Success Criteria

- [ ] What does **success look like** at the end of Phase 0?
- [ ] What does **success look like** at the end of Phase 1?
- [ ] Are there **specific demos or showcases** planned?
- [ ] What **metrics will be used** to evaluate Quantiphi's performance?

---

## Priority Questions for Day 1

### Must-Ask (Blocking Questions)
1. **Device access timeline** - When can we start hands-on work?
2. **Model availability** - When will we receive the models to optimize?
3. **Baseline metrics** - What are the current performance numbers?
4. **Target KPIs** - What specific numbers do we need to hit?
5. **Technical contact** - Who do we reach out to for daily questions?

### Should-Ask (Important for Planning)
6. Hardware specs confirmation
7. Software stack details
8. Testing data availability
9. CI/CD integration requirements
10. Security/compliance requirements

---

## Notes Section
*(Use this space during the meeting)*

### Action Items
| Item | Owner | Due Date |
|------|-------|----------|
| | | |
| | | |
| | | |

### Key Decisions Made
-
-
-

### Follow-up Required
-
-
-

### Parking Lot (Discuss Later)
-
-
-
