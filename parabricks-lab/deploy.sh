#!/bin/bash
# Ansuya's Parabricks Docker-in-Docker Workbench - Deployment Script
# Run this with cluster-admin privileges

set -e

NAMESPACE="${NAMESPACE:-hpc-workshopv1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Deploying Ansuya's Parabricks DIND Workbench"
echo "Namespace: $NAMESPACE"
echo "=========================================="

# Step 1: Grant privileged SCC
echo ""
echo "[1/4] Granting privileged SCC to service account..."
oc adm policy add-scc-to-user privileged -z ansuya-jupyter-dind -n $NAMESPACE || {
    echo "WARNING: Could not grant privileged SCC. You may need cluster-admin privileges."
    echo "Run manually: oc adm policy add-scc-to-user privileged -z ansuya-jupyter-dind -n $NAMESPACE"
}

# Step 2: Create ImageStream and BuildConfig
echo ""
echo "[2/4] Creating ImageStream and BuildConfig..."
oc apply -f "$SCRIPT_DIR/buildconfig.yaml"

# Step 3: Start build
echo ""
echo "[3/4] Starting image build (this takes 15-30 minutes)..."
oc start-build parabricks-jupyter-dind -n $NAMESPACE

echo ""
echo "Build started. You can monitor with:"
echo "  oc logs build/parabricks-jupyter-dind-1 -n $NAMESPACE --follow"
echo ""

# Step 4: Deploy (will wait for image)
echo "[4/4] Deploying workbench (pod will wait for image build to complete)..."
oc apply -f "$SCRIPT_DIR/deployment.yaml"

echo ""
echo "=========================================="
echo "Deployment initiated!"
echo "=========================================="
echo ""
echo "Monitor build progress:"
echo "  oc get builds -n $NAMESPACE | grep parabricks"
echo "  oc logs build/parabricks-jupyter-dind-1 -n $NAMESPACE --follow"
echo ""
echo "Check pod status:"
echo "  oc get pods -n $NAMESPACE | grep ansuya"
echo ""
echo "Access URL (once running):"
echo "  https://ansuya-jupyter-dind-$NAMESPACE.apps.rosa.ukhsa-rosa-eu1.j5jq.p3.openshiftapps.com/lab"
echo ""
