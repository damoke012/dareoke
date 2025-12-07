#!/bin/bash
# Honeywell Forge Cognition - Deployment Script
# Cloud-agnostic deployment for edge devices
#
# Usage:
#   ./scripts/deploy.sh docker     # Deploy with Docker Compose (single device)
#   ./scripts/deploy.sh k8s        # Deploy to Kubernetes (K3s/MicroK8s)
#   ./scripts/deploy.sh status     # Check deployment status
#   ./scripts/deploy.sh stop       # Stop deployment
#
# Environment Variables:
#   REGISTRY           - Container registry
#   VERSION            - Image version (default: latest)
#   KUBECONFIG         - Path to kubeconfig (for K8s deployment)
#   NAMESPACE          - Kubernetes namespace (default: forge-cognition)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_DIR="$PROJECT_ROOT/deployment"

# Defaults
VERSION="${VERSION:-latest}"
NAMESPACE="${NAMESPACE:-forge-cognition}"

usage() {
    echo "Forge Cognition Deployment Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  docker   Deploy with Docker Compose (for single edge device)"
    echo "  k8s      Deploy to Kubernetes cluster (K3s/MicroK8s)"
    echo "  status   Check deployment status"
    echo "  stop     Stop all services"
    echo "  logs     View logs"
    echo ""
    echo "Environment Variables:"
    echo "  REGISTRY   Container registry prefix"
    echo "  VERSION    Image version tag (default: latest)"
    echo "  NAMESPACE  K8s namespace (default: forge-cognition)"
}

deploy_docker() {
    echo "Deploying with Docker Compose..."
    cd "$DEPLOYMENT_DIR"

    # Export for docker-compose
    export VERSION
    export REGISTRY

    docker-compose up -d

    echo ""
    echo "Deployment complete!"
    echo ""
    echo "Services:"
    echo "  Inference API: http://localhost:8000"
    echo "  Health Check:  http://localhost:8000/health"
    echo "  Metrics:       http://localhost:8000/metrics"
    echo "  Prometheus:    http://localhost:9091"
    echo "  Grafana:       http://localhost:3000 (admin/admin)"
    echo ""
    echo "View logs: docker-compose logs -f forge-inference"
}

deploy_k8s() {
    echo "Deploying to Kubernetes..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo "Error: kubectl not found"
        exit 1
    fi

    # Create namespace if needed
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Apply deployment
    kubectl apply -f "$DEPLOYMENT_DIR/inference-deployment.yaml" -n "$NAMESPACE"

    echo ""
    echo "Deployment applied to namespace: $NAMESPACE"
    echo ""
    echo "Check status: kubectl get pods -n $NAMESPACE"
    echo "View logs:    kubectl logs -f deployment/forge-inference -n $NAMESPACE"
}

check_status() {
    echo "=== Docker Compose Status ==="
    if [ -f "$DEPLOYMENT_DIR/docker-compose.yaml" ]; then
        cd "$DEPLOYMENT_DIR"
        docker-compose ps 2>/dev/null || echo "Docker Compose not running"
    fi

    echo ""
    echo "=== Kubernetes Status ==="
    if command -v kubectl &> /dev/null; then
        kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "No K8s deployment found"
    else
        echo "kubectl not installed"
    fi
}

stop_deployment() {
    echo "Stopping deployments..."

    # Docker Compose
    if [ -f "$DEPLOYMENT_DIR/docker-compose.yaml" ]; then
        cd "$DEPLOYMENT_DIR"
        docker-compose down 2>/dev/null || true
        echo "Docker Compose stopped"
    fi

    # Kubernetes
    if command -v kubectl &> /dev/null; then
        kubectl delete -f "$DEPLOYMENT_DIR/inference-deployment.yaml" -n "$NAMESPACE" 2>/dev/null || true
        echo "Kubernetes deployment removed"
    fi
}

view_logs() {
    # Check Docker first
    cd "$DEPLOYMENT_DIR"
    if docker-compose ps 2>/dev/null | grep -q "forge-inference"; then
        docker-compose logs -f forge-inference
    elif command -v kubectl &> /dev/null && kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -q "forge-inference"; then
        kubectl logs -f deployment/forge-inference -n "$NAMESPACE"
    else
        echo "No running deployment found"
    fi
}

# Main
case "${1:-}" in
    docker)
        deploy_docker
        ;;
    k8s|kubernetes)
        deploy_k8s
        ;;
    status)
        check_status
        ;;
    stop)
        stop_deployment
        ;;
    logs)
        view_logs
        ;;
    *)
        usage
        exit 1
        ;;
esac
