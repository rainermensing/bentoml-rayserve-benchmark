#!/bin/bash
# Manage per-service Kind cluster
set -e

ACTION=$1
SERVICE=$2
REPLICAS=${3:-1}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLUSTER_NAME="ml-benchmark-$SERVICE"

cd "$PROJECT_DIR"

if [ "$ACTION" == "up" ]; then
    echo "=========================================="
    echo "Starting cluster $CLUSTER_NAME with $REPLICAS replicas"
    echo "=========================================="
    
    # Create cluster if not exists
    if ! kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
        kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml
    else
        echo "Cluster $CLUSTER_NAME already exists"
        kubectl config use-context "kind-$CLUSTER_NAME"
    fi

    # Load image
    IMAGE="ml-benchmark/$SERVICE-mobilenet:latest"
    echo ""
    echo "Loading image $IMAGE..."
    kind load docker-image "$IMAGE" --name "$CLUSTER_NAME"

    # Apply common resources
    echo ""
    echo "Applying Kubernetes manifests..."
    kubectl apply -f kubernetes/namespace.yaml

    # Apply service-specific resources
    if [ "$SERVICE" == "rayserve" ]; then
        kubectl apply -f kubernetes/rayserve-configmap.yaml
    fi

    # Apply deployment
    MANIFEST="kubernetes/$SERVICE-deployment.yaml"
    kubectl apply -f "$MANIFEST"
    
    # Scale to desired replicas
    DEPLOYMENT_NAME="$SERVICE-mobilenet"
    echo "Scaling $DEPLOYMENT_NAME to $REPLICAS replicas..."
    kubectl scale deployment "$DEPLOYMENT_NAME" --replicas="$REPLICAS" -n ml-benchmark

    echo ""
    echo "Waiting for $DEPLOYMENT_NAME to be ready..."
    kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n ml-benchmark --timeout=300s

    echo ""
    echo "Deployment Status:"
    kubectl get pods -n ml-benchmark
    echo ""

elif [ "$ACTION" == "down" ]; then
    echo "=========================================="
    echo "Deleting cluster $CLUSTER_NAME"
    echo "=========================================="
    kind delete cluster --name "$CLUSTER_NAME"
else
    echo "Usage: $0 up|down <service> [replicas]"
    exit 1
fi
