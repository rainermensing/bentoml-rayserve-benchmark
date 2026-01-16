#!/bin/bash
# Deploy all resources to Kind Kubernetes cluster
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Deploying to Kubernetes (Kind)"
echo "=========================================="

# Check if Kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "ml-benchmark"; then
    echo "Creating Kind cluster..."
    kind create cluster --config kind-config.yaml
else
    echo "Kind cluster 'ml-benchmark' already exists"
    kubectl config use-context kind-ml-benchmark
fi

# Load Docker images into Kind
echo ""
echo "Loading Docker images into Kind cluster..."
kind load docker-image ml-benchmark/bentoml-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/fastapi-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/rayserve-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/locust-service:latest --name ml-benchmark

# Apply Kubernetes manifests
echo ""
echo "Applying Kubernetes manifests..."
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/bentoml-deployment.yaml
kubectl apply -f kubernetes/fastapi-deployment.yaml
kubectl apply -f kubernetes/rayserve-deployment.yaml
kubectl apply -f kubernetes/locust-service-deployment.yaml

# Wait for deployments
echo ""
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/bentoml-mobilenet -n ml-benchmark --timeout=300s || true
kubectl rollout status deployment/fastapi-mobilenet -n ml-benchmark --timeout=300s || true
kubectl rollout status deployment/rayserve-mobilenet -n ml-benchmark --timeout=300s || true
kubectl rollout status deployment/locust-master -n ml-benchmark --timeout=120s || true

# Show status
echo ""
echo "=========================================="
echo "Deployment Status"
echo "=========================================="
kubectl get pods -n ml-benchmark
echo ""
kubectl get svc -n ml-benchmark
echo ""
echo "Services are accessible at:"
echo "  - BentoML:   http://localhost:3000"
echo "  - FastAPI:   http://localhost:8000"
echo "  - Ray Serve: http://localhost:31800"
echo "  - Locust UI: http://localhost:8089"
