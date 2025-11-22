# OpenShift Basics Lab - Jobs vs Deployments

**Duration**: 10-15 minutes
**Audience**: Developers
**Interface**: OpenShift Web Console

---

## Overview

Learn the fundamental difference between **Jobs** (run-once tasks) and **Deployments** (always-running services) using the OpenShift web interface.

## What You'll Learn

- ✅ When to use Jobs vs Deployments
- ✅ Deploy workloads via OpenShift UI
- ✅ Monitor pods, view logs, and check events
- ✅ Understand self-healing and scaling

---

## Prerequisites

Before starting this lab, you need:

### 1. OpenShift Cluster Access

**From Your Platform Team, Get:**
- OpenShift Console URL: `https://console-openshift-console.apps.[CLUSTER-DOMAIN]`
- Your username and password
- Project/namespace name assigned to you

**Example:**
```
Console URL: https://console-openshift-console.apps.prod.company.com
Username: jdoe
Password: [provided by admin]
Project: dev-team-sandbox
```

### 2. How to Get This Information

**Ask your platform team:**
```
Hi [Platform Team],

I need access for the OpenShift Basics Lab. Can you provide:
1. OpenShift Console URL
2. My username/password (or SSO instructions)
3. Project/namespace I can use for testing

Thanks!
```

**Or check your platform documentation** for:
- Self-service portal
- Onboarding guide
- Internal wiki/confluence pages

---

## Lab Files

| File | Description |
|------|-------------|
| `job-example.yaml` | Job that runs once (batch processing demo) |
| `deployment-example.yaml` | Deployment that runs continuously (service demo) |
| `LAB_GUIDE.md` | Step-by-step instructions |
| `PRESENTATION_SCRIPT.md` | 10-15 min presentation guide |

---

## Quick Start

### Option 1: Developer Perspective (Recommended)

1. Login to OpenShift Console
2. Switch to **Developer** perspective (top-left dropdown)
3. Select your project
4. Click **+Add** → **Import YAML**
5. Paste `job-example.yaml` → Create
6. Follow [LAB_GUIDE.md](LAB_GUIDE.md)

### Option 2: Administrator Perspective

1. Login to OpenShift Console
2. Go to **Workloads** → **Jobs**
3. Click **Create Job**
4. Paste `job-example.yaml` → Create
5. Follow [LAB_GUIDE.md](LAB_GUIDE.md) (Administrator View section)

---

## Customizing for Your Environment

### Update Namespace

Before deploying, update the `namespace` field in both YAML files:

**Find this line:**
```yaml
metadata:
  name: data-processing-job
  namespace: parabricks-test  # ← CHANGE THIS
```

**Replace with your project:**
```yaml
metadata:
  name: data-processing-job
  namespace: YOUR-PROJECT-NAME  # ← Use your assigned project
```

### Verify Image Access

The lab uses public Red Hat images:
```yaml
image: registry.access.redhat.com/ubi8/ubi-minimal:latest
```

**If your cluster has restricted internet access:**
- Check with platform team if this image is mirrored internally
- They may provide alternative image URL like:
  ```yaml
  image: internal-registry.company.com/redhat/ubi8-minimal:latest
  ```

---

## Key Concepts

### Job
- **Purpose**: Run a task once and complete
- **Use Cases**: Data processing, batch jobs, reports, migrations
- **Behavior**: Starts → Runs → Completes → Stops
- **Restart**: No automatic restart

### Deployment
- **Purpose**: Keep service always running
- **Use Cases**: Web APIs, microservices, databases, message queues
- **Behavior**: Starts → Runs forever → Self-heals if crashes
- **Restart**: Automatic restart and self-healing

---

## Next Steps

After completing this lab:

1. **Explore Services**: Expose your Deployment with a Service
2. **Try Routes**: Make your app accessible externally
3. **Add ConfigMaps**: Externalize configuration
4. **Use Secrets**: Store sensitive data securely
5. **Set Resource Limits**: Control CPU/Memory usage

---

## Troubleshooting

### Can't Login

**Problem**: Console URL doesn't work
**Solution**: Verify URL with platform team, check VPN connection

### No Projects Visible

**Problem**: Don't see any projects
**Solution**: Request project access from platform team

### Images Won't Pull

**Problem**: "ImagePullBackOff" error
**Solution**: Check with platform team about:
- Image registry access
- Internal mirror locations
- Network policies

### Permission Denied

**Problem**: Can't create resources
**Solution**: Request proper RBAC permissions:
- `edit` role for full access
- `view` role for read-only

---

## Support

**Platform Team Contact**: [INSERT YOUR TEAM CONTACT]
**Internal Documentation**: [INSERT WIKI/CONFLUENCE LINK]
**Slack Channel**: [INSERT SLACK CHANNEL]

---

## License

Internal use only - [Your Company Name]
