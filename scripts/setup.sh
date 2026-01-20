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
echo "Step 1: Downloading MobileNetV2 model (uvx python3.11)..."
if [ ! -f "model/mobilenet_v2.keras" ]; then
    uvx --python 3.11 --with tensorflow==2.16.1 --with "numpy>=1.24.0,<2.0.0" python model/download_model.py
else
    echo "Model already exists, skipping download"
fi

# Step 2: Prepare BentoML service
echo ""
echo "Step 2: Preparing BentoML service..."


# Step 3: Build images (uses uvx with Python 3.10 for Bento)
echo ""
echo "Step 3: Building Docker images..."
"$SCRIPT_DIR/build-images.sh"

# Show status
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Docker images have been built. To run the benchmark (which manages its own clusters):"
echo "  make loadtest"
echo ""
echo "To deploy a specific service for manual testing:"
echo "  ./scripts/deploy-k8s.sh bentoml"
