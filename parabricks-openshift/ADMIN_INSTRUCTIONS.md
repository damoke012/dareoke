# Admin Instructions: Make Parabricks Workbench Globally Available

## Context
We have built a custom Jupyter workbench image with Clara Parabricks for genomics analysis. The image is currently only available in the `parabricks` namespace. We need to make it globally available in Red Hat OpenShift AI so all users can select it from the notebook image dropdown.

## Current Image Location
- **Namespace**: `parabricks`
- **ImageStream**: `parabricks-workbench`
- **Full Path**: `image-registry.openshift-image-registry.svc:5000/parabricks/parabricks-workbench:latest`
- **SHA**: `sha256:084c11248480d552ee6aa3af4b9c4913868de2af3247c406a1440db34bb9d302`

## What the Admin Needs to Do

### Option 1: Create ImageStream in redhat-ods-applications (Recommended)

As a cluster admin, run this command:

```bash
oc apply -f global-workbench-imagestream.yaml
```

Or manually create the ImageStream:

```bash
cat <<EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: parabricks-workbench
  namespace: redhat-ods-applications
  labels:
    app.kubernetes.io/created-by: byon
    opendatahub.io/notebook-image: "true"
  annotations:
    opendatahub.io/notebook-image-url: "https://github.com/NVIDIA/clara-parabricks"
    opendatahub.io/notebook-image-name: "Clara Parabricks Workbench"
    opendatahub.io/notebook-image-desc: "Jupyter environment with NVIDIA Clara Parabricks for genomics analysis. Includes BioPython, PySam, and other genomics tools."
    opendatahub.io/notebook-image-order: "100"
spec:
  lookupPolicy:
    local: true
  tags:
  - name: "2025.1"
    annotations:
      opendatahub.io/notebook-software: '[{"name":"Python","version":"3.12"},{"name":"Clara Parabricks","version":"4.6.0-1"}]'
      opendatahub.io/notebook-python-dependencies: '[{"name":"BioPython","version":"1.86"},{"name":"PySam","version":"0.23.3"},{"name":"Pandas","version":"2.3.2"},{"name":"Matplotlib","version":"3.10.6"},{"name":"Seaborn","version":"0.13.2"}]'
      openshift.io/imported-on: "2025-11-14"
    from:
      kind: DockerImage
      name: image-registry.openshift-image-registry.svc:5000/parabricks/parabricks-workbench:latest
    importPolicy:
      importMode: Legacy
    referencePolicy:
      type: Local
EOF
```

### Option 2: Grant Permissions to Allow Image Pulling from Other Namespaces

Alternatively, grant system:image-puller role to the service account:

```bash
oc policy add-role-to-user system:image-puller \
  system:serviceaccount:redhat-ods-applications:notebook-controller-service-account \
  -n parabricks
```

## Verification

After the admin creates the ImageStream, verify it's available:

```bash
# Check the ImageStream exists
oc get imagestream parabricks-workbench -n redhat-ods-applications

# Verify the annotations
oc get imagestream parabricks-workbench -n redhat-ods-applications -o yaml | grep opendatahub
```

## Expected Result

After the admin completes this, the "Clara Parabricks Workbench" image will appear in the notebook image dropdown when creating a new workbench in Red Hat OpenShift AI.

Users will see:
- **Image Name**: Clara Parabricks Workbench
- **Description**: Jupyter environment with NVIDIA Clara Parabricks for genomics analysis
- **Python Version**: 3.12
- **Included Libraries**: BioPython, PySam, Pandas, Matplotlib, Seaborn

## Alternative: Users Can Still Use Custom Image Path

Until the admin makes this change, users can manually enter the custom image path when creating a workbench:

```
image-registry.openshift-image-registry.svc:5000/parabricks/parabricks-workbench:latest
```

## Contact

For questions about this setup, contact: Dare.Oke@ext.quantiphi.com
