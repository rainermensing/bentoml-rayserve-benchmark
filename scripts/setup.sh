#!/bin/bash
# Complete setup script for BentoML vs FastAPI benchmark
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "BentoML vs FastAPI Benchmark Setup"
echo "=========================================="

# Check prerequisites
echo ""
echo "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v kind >/dev/null 2>&1 || { echo "❌ Kind is required. Install with: brew install kind"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required. Install with: brew install kubectl"; exit 1; }
command -v uv >/dev/null 2>&1 || { echo "❌ uv is required. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"; exit 1; }

echo "✅ All prerequisites found"

echo "=========================================="

# Step 1: Download model with uvx (no virtualenv)
echo ""
echo "Step 1: Downloading MobileNetV2 model (uvx python3.10)..."
if [ ! -f "model/mobilenet_v2.keras" ]; then
    uvx --python 3.10 --with tensorflow==2.15.0 --with "numpy>=1.24.0,<2.0.0" python model/download_model.py
else
    echo "Model already exists, skipping download"
fi

# Step 2: Prepare BentoML service
echo ""
echo "Step 2: Preparing BentoML service..."
cp model/mobilenet_v2.keras bentoml/
cp model/imagenet_labels.txt bentoml/

# Step 3: Build images (uses uvx with Python 3.10 for Bento)
echo ""
echo "Step 3: Building Docker images..."
"$SCRIPT_DIR/build-images.sh"

# Step 4: Deploy to Kubernetes
echo ""
echo "Step 4: Deploying to Kubernetes..."
"$SCRIPT_DIR/deploy-k8s.sh"

# Step 5: Wait for pods
echo ""
echo "Step 5: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=locust -n ml-benchmark --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=bentoml-mobilenet -n ml-benchmark --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=fastapi-mobilenet -n ml-benchmark --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=rayserve-mobilenet -n ml-benchmark --timeout=300s || true

# Show status
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
kubectl get pods -n ml-benchmark
echo ""
echo "Services available at:"
echo "  - BentoML:   http://localhost:3000"
echo "  - FastAPI:   http://localhost:8000"
echo "  - Ray Serve: http://localhost:31800"
echo "  - Locust UI: http://localhost:8089"
echo ""
echo "To run load tests, open http://localhost:8089 in your browser"
echo "Or run: ./scripts/automated-loadtest.sh"
