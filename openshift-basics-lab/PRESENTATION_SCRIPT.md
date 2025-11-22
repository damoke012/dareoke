# OpenShift Basics - Presentation Script (10-15 minutes)

**Presenter**: [Your Name]
**Audience**: Developers
**Duration**: 10-15 minutes
**Format**: Live demo with explanations

---

## Presentation Structure

| Section | Duration | Content |
|---------|----------|---------|
| Introduction | 2 min | What we'll cover, why it matters |
| Jobs Demo | 4 min | Deploy Job, show logs, explain use cases |
| Deployments Demo | 4 min | Deploy Deployment, show self-healing, scaling |
| Monitoring | 3 min | Logs, events, metrics |
| Q&A | 2 min | Questions and next steps |

---

## Before You Present

### Preparation Checklist

- [ ] Login to OpenShift Console
- [ ] Have your project/namespace ready
- [ ] Update YAML files with correct namespace
- [ ] Test both deployments work
- [ ] Clean up any old resources
- [ ] Have presentation open in separate window
- [ ] Prepare for screen sharing

### Pre-Demo Cleanup

```bash
# Delete any existing resources
oc delete job data-processing-job -n [YOUR-PROJECT]
oc delete deployment web-service -n [YOUR-PROJECT]
```

---

## Presentation Script

### **Slide 1: Introduction (2 minutes)**

**SAY:**
> "Good morning/afternoon everyone! Today we're going to learn about two fundamental workload types in OpenShift: Jobs and Deployments.
>
> By the end of this session, you'll understand:
> - When to use Jobs versus Deployments
> - How to deploy them using the OpenShift web console
> - How to monitor and troubleshoot your workloads
>
> This is hands-on - you can follow along if you have access to our OpenShift cluster."

**SHOW:**
- OpenShift Console login page
- Quick navigation of the UI

**KEY POINTS:**
- Jobs = Run once (batch processing, data pipelines, reports)
- Deployments = Always running (APIs, microservices, databases)

---

### **Slide 2: Jobs Demo (4 minutes)**

**SAY:**
> "Let's start with Jobs. A Job runs a task once and then stops. Think of it like running a script - it executes, completes, and exits.
>
> Common use cases:
> - Processing a batch of data
> - Generating reports
> - Database migrations
> - Training ML models
>
> Let me show you how to create one."

**DEMO STEPS:**

1. **Navigate** (30 seconds)
   ```
   Developer Perspective → +Add → Import YAML
   (Or: Administrator → Workloads → Jobs → Create Job)
   ```

2. **Paste YAML** (30 seconds)
   - Show the `job-example.yaml`
   - Highlight key fields:
     ```yaml
     kind: Job                    # ← This makes it a Job
     restartPolicy: Never         # ← Don't restart when done
     ```

3. **Create** (30 seconds)
   - Click Create
   - Navigate to Topology (Developer) or Jobs list (Administrator)

4. **Watch Execution** (2 minutes)
   - **SAY:** "Watch the job run... it'll take about 20 seconds"
   - Show status changing: Pending → Running → Completed
   - Click on Job → Click on Pod → View Logs

5. **Show Logs** (1 minute)
   - **SAY:** "Here's the output. The job loaded data, processed it in batches, and generated a report."
   - Scroll through the log output
   - Point out:
     ```
     Step 1: Loading data...
     Step 2: Processing records...
     JOB COMPLETED SUCCESSFULLY
     ```

**KEY POINTS:**
- **SAY:** "Notice the pod status is 'Completed' - it's stopped and won't restart."
- "If you need to run it again, you create a new Job or use a CronJob for scheduled runs."

---

### **Slide 3: Deployments Demo (4 minutes)**

**SAY:**
> "Now let's look at Deployments. Unlike Jobs, Deployments keep your application running continuously.
>
> Use Deployments for:
> - REST APIs
> - Web applications
> - Microservices
> - Databases
> - Any service that needs to be always available
>
> The key feature: self-healing. If a pod crashes, OpenShift automatically restarts it."

**DEMO STEPS:**

1. **Navigate** (30 seconds)
   ```
   +Add → Import YAML
   (Or: Workloads → Deployments → Create Deployment)
   ```

2. **Paste YAML** (30 seconds)
   - Show `deployment-example.yaml`
   - Highlight key fields:
     ```yaml
     kind: Deployment             # ← Always running
     replicas: 2                  # ← Run 2 copies
     ```

3. **Create** (30 seconds)
   - Click Create
   - Show 2 pods being created

4. **Show Running State** (1 minute)
   - Click Deployment → Click a Pod → Logs tab
   - **SAY:** "See the heartbeat messages? This pod is running continuously, printing status every 30 seconds."
   - Let it run for a moment to show ongoing logs

5. **Demo Self-Healing** (1.5 minutes)
   - **SAY:** "Now watch this - I'm going to delete one pod..."
   - Actions → Delete Pod → Confirm
   - **SAY:** "...and OpenShift automatically creates a new one to maintain 2 replicas."
   - Show: Pod terminating + New pod creating
   - **KEY POINT:** "This is self-healing in action. Your service stays available even if pods crash."

6. **Demo Scaling** (30 seconds)
   - Details tab → Pod count → Click up arrow
   - **SAY:** "I can easily scale to 3 replicas..."
   - Show 3rd pod being created
   - Click down arrow back to 1
   - **SAY:** "...or scale down when I don't need the capacity."

**KEY POINTS:**
- "Deployments ensure your service is always running"
- "You get self-healing, scaling, and zero-downtime updates"
- "Perfect for production workloads"

---

### **Slide 4: Monitoring & Debugging (3 minutes)**

**SAY:**
> "Let's quickly look at how to monitor and troubleshoot your workloads."

**DEMO STEPS:**

1. **Logs** (1 minute)
   - Show Job logs (static, complete output)
   - Show Deployment logs (streaming, ongoing)
   - **SAY:** "Logs show your application output - essential for debugging."

2. **Events** (1 minute)
   - Click Events tab
   - **SAY:** "Events show what OpenShift is doing - pulling images, creating containers, etc."
   - Point out:
     ```
     Successfully pulled image...
     Created container...
     Started container...
     ```

3. **Metrics** (1 minute)
   - Click Metrics tab
   - Show CPU and Memory graphs
   - **SAY:** "Metrics help you understand resource usage and identify performance issues."
   - Point to spikes or patterns

**KEY POINTS:**
- "Three tools for debugging: Logs, Events, Metrics"
- "Logs = Application output"
- "Events = Kubernetes actions"
- "Metrics = Resource usage"

---

### **Slide 5: Summary & Next Steps (2 minutes)**

**SAY:**
> "Let's recap what we learned today..."

**SHOW COMPARISON:**

| Aspect | Job | Deployment |
|--------|-----|------------|
| **Purpose** | Run once | Always running |
| **Completion** | Stops when done | Runs forever |
| **Self-Healing** | No | Yes |
| **Scaling** | Not applicable | Easy scaling |
| **Use Case** | Batch processing | Services/APIs |

**NEXT STEPS:**

**SAY:**
> "To try this yourself:
> 1. Clone the repo: `git clone [REPO-URL]`
> 2. Follow the LAB_GUIDE.md
> 3. Update namespace to your assigned project
> 4. Deploy and experiment!
>
> Advanced topics to explore:
> - Services (expose your Deployment)
> - Routes (external access)
> - ConfigMaps and Secrets
> - Resource limits and requests
> - Health checks (liveness/readiness probes)"

**SHARE RESOURCES:**
- Repository URL: `[INSERT YOUR GITHUB URL]`
- Internal docs: `[INSERT WIKI/CONFLUENCE]`
- Platform team contact: `[INSERT SLACK/EMAIL]`

---

### **Q&A (2 minutes)**

**Common Questions:**

**Q: Can a Job run multiple times?**
**A:** "A Job runs once. For scheduled recurring tasks, use CronJobs. Or delete and recreate the Job."

**Q: What happens if a Deployment pod crashes?**
**A:** "OpenShift automatically restarts it. That's the self-healing we just saw."

**Q: How many replicas should I use?**
**A:** "Start with 2-3 for high availability. Scale based on load testing and monitoring."

**Q: Can I update a running Deployment?**
**A:** "Yes! OpenShift does rolling updates with zero downtime. We can cover that in a future session."

**Q: What about database migrations?**
**A:** "Perfect use case for Jobs! They ensure migrations run once before your app deploys."

**Q: How do I access my Deployment from outside?**
**A:** "Create a Service to expose internally, then a Route for external access. That's our next topic!"

---

## After the Presentation

### Follow-Up Email Template

```
Subject: OpenShift Basics Lab - Resources

Hi Team,

Thanks for attending today's session on Jobs vs Deployments!

Here are the resources:
- GitHub Repo: [INSERT URL]
- Lab Guide: [LINK TO LAB_GUIDE.md]
- Recording: [IF RECORDED]

To try the lab:
1. Request access to our dev OpenShift cluster (if you don't have it)
2. Clone the repo
3. Follow LAB_GUIDE.md
4. Reach out on #openshift-help if you have questions

Next Session:
[INSERT NEXT TOPIC AND DATE]

Happy learning!
[Your Name]
```

---

## Tips for Success

### Presenting Tips

✅ **DO:**
- Speak slowly and clearly
- Explain WHAT you're doing before clicking
- Pause after creating resources (let them appear)
- Acknowledge when something takes time ("This will take 20 seconds...")
- Use simple language (avoid jargon)

❌ **DON'T:**
- Click too fast
- Assume everyone knows the UI
- Skip over errors (acknowledge and explain)
- Use acronyms without explaining (e.g., say "Continuous Integration/Continuous Deployment" not just "CI/CD")

### Technical Tips

✅ **Prepare:**
- Test everything before presenting
- Have YAML files ready in separate window
- Clear old resources beforehand
- Check image pull works
- Have backup plan if demo fails

✅ **During Demo:**
- Zoom in browser (Ctrl/Cmd +)
- Close unnecessary tabs
- Use full screen
- Keep mouse movements slow
- Highlight what you're clicking

### Troubleshooting During Demo

**If Job fails to start:**
- Check Events tab for errors
- Verify namespace is correct
- Check image pull (ImagePullBackOff = image issue)

**If Deployment pods won't start:**
- Check resource quotas (oc describe quota)
- Verify image accessibility
- Look at Events for specific error

**If UI is slow:**
- Refresh browser
- Check cluster status with platform team
- Have CLI commands ready as backup

---

## Presenter Notes

### Time Management

- **2 min intro**: Quick, high-level, set expectations
- **4 min Jobs**: One example, clear explanation, show logs
- **4 min Deployments**: Show self-healing (key differentiator), quick scale demo
- **3 min Monitoring**: Fast overview of 3 tools (logs/events/metrics)
- **2 min wrap**: Summary table, next steps, Q&A

**If running over time:**
- Skip scaling demo
- Shorten monitoring to just logs
- Defer detailed Q&A to Slack/email

**If running under time:**
- Show more metrics details
- Demonstrate additional features (resource limits, probes)
- Take more questions

### Audience Adaptation

**For junior developers:**
- Explain more basics (what is a pod, container, etc.)
- Use more analogies (Job = script, Deployment = server process)
- Go slower through UI

**For experienced developers:**
- Move faster through basics
- Show YAML structure more
- Discuss advanced topics (resource limits, probes, strategies)

---

## Backup Plan

**If live demo fails:**

1. **Have screenshots** of each step
2. **Pre-record** the demo as backup
3. **Explain** from YAML files without deploying
4. **Reschedule** if major cluster issues

---

## Success Metrics

After presentation, measure success by:

- [ ] Number of attendees who clone the repo
- [ ] Questions asked (engagement)
- [ ] Follow-up lab completions
- [ ] Feedback survey responses

**Survey Questions:**
1. How clear was the explanation of Jobs vs Deployments? (1-5)
2. Was the demo helpful? (1-5)
3. Will you try the lab? (Yes/No)
4. What topics should we cover next?

---

Good luck with your presentation! 🚀
