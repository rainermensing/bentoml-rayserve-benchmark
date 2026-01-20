#!/bin/bash
# Cleanup all resources
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Cleaning Up Resources"
echo "=========================================="

# Delete Kind clusters
echo ""
echo "Deleting Kind clusters..."
kind delete cluster --name ml-benchmark 2>/dev/null || true
kind delete cluster --name ml-benchmark-bentoml 2>/dev/null || true
kind delete cluster --name ml-benchmark-fastapi 2>/dev/null || true
kind delete cluster --name ml-benchmark-rayserve 2>/dev/null || true

# Remove Docker images (optional)
read -p "Remove Docker images? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing Docker images..."
    docker rmi ml-benchmark/bentoml-mobilenet:latest 2>/dev/null || true
    docker rmi ml-benchmark/fastapi-mobilenet:latest 2>/dev/null || true
    docker rmi ml-benchmark/rayserve-mobilenet:latest 2>/dev/null || true
    #docker rmi ml-benchmark/locust-service:latest 2>/dev/null || true
fi

# Remove virtual environment (optional)
read -p "Remove virtual environment? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing virtual environment..."
    rm -rf .venv
fi

# Remove model files from bentoml directory
echo "Cleaning up copied model files..."
rm -f bentoml/mobilenet_v2.keras
rm -f bentoml/imagenet_labels.txt

echo ""
echo "=========================================="
echo "Cleanup Complete"
echo "=========================================="
