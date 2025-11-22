# GPU Lab Demo - Speaker Notes

**Total Time: 10-12 minutes**
**Format: Demo walkthrough + Hands-on lab**

---

## Opening (30 seconds)

> "Now let's look at GPU workloads in ROSA. We'll submit a GPU test Job, monitor the pods, and check the logs to see the GPU statistics."

---

## DEMO: Building the GPU Test Job (3 minutes)

### Slide/Screen: Show the Job YAML

> "Here's our GPU test Job. A few key things to notice:"

**Point 1: Resource Requests (15 sec)**
> "Under resources, we request `nvidia.com/gpu: 1`. This tells the scheduler we need one GPU. Without this, we won't get GPU access."

**Point 2: Tolerations (15 sec)**
> "The tolerations section allows our pod to be scheduled on GPU nodes, which typically have taints to prevent non-GPU workloads from being scheduled there."

**Point 3: The Test Script (30 sec)**
> "The script runs nvidia-smi to detect GPUs, reports memory info, CUDA version, and current utilization. This is exactly what you'd do to verify GPU access in any application."

### Create the Job (30 sec)

```bash
# In terminal
oc apply -f gpu-test-job.yaml
```

> "We apply the Job... and it's created. Now let's watch what happens."

---

## LAB: Submit Job, Monitor Pods, Check Logs (4 minutes)

### Step 1: Watch Pod Creation (45 sec)

```bash
oc get pods -w
```

> "The pod starts in Pending state while the scheduler finds a GPU node. Then ContainerCreating as it pulls the CUDA image. And now it's Running."

> "Notice it completes quickly - that's because this is a Job. It runs once and stops, unlike a Deployment which keeps running."

**Key Point:**
> "If your pod stays Pending, check Events - you might not have enough GPU quota or available GPU nodes."

### Step 2: Check the Logs (1 min)

```bash
oc logs job/gpu-test-job
```

> "Here we see the nvidia-smi output. We can see:
> - The GPU model (Tesla T4)
> - Memory available (15GB)
> - CUDA version (12.4)
> - Current utilization (0% because nothing else is using it)"

**Highlight:**
> "This is exactly the information your applications need to verify GPU access. If you see this output, your GPU workload is ready to go."

### Step 3: Check Job Status (30 sec)

```bash
oc get jobs
```

> "The Job shows Completions 1/1 - it succeeded. If it failed, you'd see 0/1 and need to check the logs for errors."

```bash
oc describe job gpu-test-job
```

> "The describe shows duration, pod name, and any events. Useful for debugging."

### Step 4: View Events (45 sec)

```bash
oc get events --field-selector involvedObject.name=gpu-test-job
```

> "Events show the timeline: Scheduled, Pulled image, Created container, Started container. If something fails, this tells you where it broke."

---

## DEMO: GPU Profile Job (3 minutes)

> "Now let's run a more realistic GPU workload - a PyTorch benchmark that actually uses the GPU for computation."

### Submit the Profile Job (30 sec)

```bash
oc apply -f gpu-profile-job.yaml
```

> "This job uses PyTorch to run matrix multiplications on the GPU - a common operation in machine learning."

### Monitor and View Logs (1.5 min)

```bash
# Wait for completion
oc get pods -l app=gpu-profile -w

# Once completed
oc logs job/gpu-profile-job
```

> "The output shows:
> - GPU properties (compute capability, memory)
> - Memory allocation benchmarks
> - Matrix multiplication performance in GFLOPS
> - Memory usage summary"

**Key Insight:**
> "This tells you how fast your GPU is for actual compute workloads. A Tesla T4 typically gets 8-10 TFLOPS for this benchmark."

### Explain Use Cases (1 min)

> "When would you use a profile job?
> - Validating a new GPU node type
> - Benchmarking before running expensive ML training
> - Troubleshooting performance issues
> - Comparing different GPU configurations"

---

## Cleanup (30 seconds)

```bash
# Jobs auto-cleanup after 5 minutes, or manually:
oc delete job gpu-test-job gpu-profile-job
```

> "Jobs have a TTL setting - they clean themselves up after 5 minutes. Or delete manually when done testing."

---

## Summary Points (30 seconds)

> "Key takeaways:
> 1. **Request GPUs explicitly** - use `nvidia.com/gpu` in resources
> 2. **Jobs run once and complete** - perfect for testing and batch processing
> 3. **Check logs for GPU info** - nvidia-smi tells you everything
> 4. **Profile before production** - verify performance meets your needs"

---

## Common Questions & Answers

**Q: What if the pod stays Pending?**
> "Check `oc describe pod` for Events. Usually it's quota limits or no available GPU nodes."

**Q: How do I request multiple GPUs?**
> "Set `nvidia.com/gpu: 2` or more. The pod gets exclusive access to those GPUs."

**Q: Can multiple pods share a GPU?**
> "By default, no. Each GPU is assigned to one pod. MIG (Multi-Instance GPU) allows sharing on newer GPUs."

**Q: How do I know which GPU type I got?**
> "Check nvidia-smi output in logs. It shows the exact model."

---

## Timing Checkpoints

| Section | Duration | Cumulative |
|---------|----------|------------|
| Opening | 0:30 | 0:30 |
| Demo: Show YAML | 1:30 | 2:00 |
| Lab: Submit & Monitor | 4:00 | 6:00 |
| Demo: Profile Job | 3:00 | 9:00 |
| Cleanup & Summary | 1:00 | 10:00 |

**Buffer: 2 minutes for questions/issues**

---

## Pre-Demo Checklist

- [ ] GPU nodes available in cluster
- [ ] Namespace has GPU quota
- [ ] YAML files ready in terminal
- [ ] Previous jobs cleaned up
- [ ] Screen visible to audience

---

## Backup Commands

If something fails:

```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU quota
oc describe quota

# Check all pods in namespace
oc get pods

# Force delete stuck job
oc delete job gpu-test-job --force --grace-period=0
```

---

## Transition to Next Section

> "So that's GPU Jobs - submit, monitor, check logs. Next, [Nishant will show / we'll look at] ..."

---

**END OF SPEAKER NOTES**
