# KIA Lab Build Files

All Dockerfiles and dependencies for RHOAI custom workbench images.

## Images

| Image | Namespace | BuildConfig | Dockerfile |
|-------|-----------|-------------|------------|
| Agentic Lab | agenticlab | agentic-lab-custom | Dockerfile.agentic-lab |
| RAG Lab | raglab | rag-lab-build | Dockerfile.rag-lab |
| Finetuning Lab | hpc-workshopv1 | finetuning-lab-build | Dockerfile.finetuning-lab |
| CV Lab | hpc-workshopv1 | cv-lab-custom | Dockerfile.cv-lab |
| KIA PyTorch | hpc-workshopv1 | kia-pytorch | Dockerfile.kia-pytorch |

## Build Commands

### From OpenShift Console
1. Go to Builds > BuildConfigs
2. Select the BuildConfig
3. Actions > Start Build

### From CLI
```bash
# CV Lab
oc start-build cv-lab-custom -n hpc-workshopv1 --follow

# Agentic Lab
oc start-build agentic-lab-custom -n agenticlab --follow

# RAG Lab
oc start-build rag-lab-build -n raglab --follow

# Finetuning Lab
oc start-build finetuning-lab-build -n hpc-workshopv1 --follow

# KIA PyTorch
oc start-build kia-pytorch -n hpc-workshopv1 --follow
```

## Dependencies

### Poetry-based images (Agentic, RAG, Finetuning)
Each has:
- `<name>-pyproject.toml` - Python dependencies
- `<name>-poetry.lock` - Locked versions

### Pip-based images (CV Lab, KIA PyTorch)
- `requirements.txt` - For kia-pytorch
- CV Lab installs packages directly in Dockerfile

## Image Pull Permissions

If workbenches can't pull images, run:
```bash
oc policy add-role-to-user system:image-puller system:serviceaccount:redhat-ods-applications:default -n <image-namespace>
```

## Git Source

All BuildConfigs pull from:
- **Repo:** https://github.com/damoke012/dareoke.git
- **Branch:** master
- **Context:** kia-lab-builds
