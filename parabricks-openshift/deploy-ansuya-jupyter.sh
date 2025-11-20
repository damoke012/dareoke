#!/bin/bash
# Deploy Ansuya's Parabricks Jupyter environment
# Usage: ./deploy-ansuya-jupyter.sh

set -e

NAMESPACE="parabricks"
IMAGE_NAME="parabricks-jupyter-bakta"

echo "=== Deploying Ansuya Jupyter Environment ==="

# 1. Create namespace if not exists
echo "Creating namespace..."
oc create namespace $NAMESPACE --dry-run=client -o yaml | oc apply -f -

# 2. Create BuildConfig for the image
echo "Creating BuildConfig..."
cat <<EOF | oc apply -f -
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: $IMAGE_NAME
  namespace: $NAMESPACE
spec:
  source:
    type: Dockerfile
    dockerfile: |
$(sed 's/^/      /' Dockerfile.jupyter-bakta)
  strategy:
    type: Docker
    dockerStrategy:
      from:
        kind: DockerImage
        name: image-registry.openshift-image-registry.svc:5000/redhat-ods-applications/jupyter-datascience-cpu-py312-ubi9:2025.1
  output:
    to:
      kind: ImageStreamTag
      name: $IMAGE_NAME:latest
  resources:
    limits:
      memory: "8Gi"
      cpu: "4"
EOF

# 3. Create ImageStream
echo "Creating ImageStream..."
cat <<EOF | oc apply -f -
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: $IMAGE_NAME
  namespace: $NAMESPACE
EOF

# 4. Start the build
echo "Starting build..."
oc start-build $IMAGE_NAME -n $NAMESPACE --follow

# 5. Deploy the application
echo "Deploying application..."
oc apply -f ansuya-jupyter-deployment.yaml

# 6. Wait for deployment
echo "Waiting for deployment to be ready..."
oc rollout status deployment/ansuya-jupyter -n $NAMESPACE --timeout=300s

# 7. Get the URL and token
echo ""
echo "=== Deployment Complete ==="
POD=$(oc get pods -n $NAMESPACE -l app=ansuya-jupyter -o jsonpath='{.items[0].metadata.name}')
ROUTE=$(oc get route ansuya-jupyter -n $NAMESPACE -o jsonpath='{.spec.host}')

echo "Pod: $POD"
echo "Route: https://$ROUTE"
echo ""
echo "To get the token, run:"
echo "oc logs -n $NAMESPACE $POD | grep token"
echo ""
echo "To access JupyterLab:"
echo "https://$ROUTE/lab?token=<TOKEN>"
