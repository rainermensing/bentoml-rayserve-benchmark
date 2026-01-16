#!/bin/bash
# Run load tests using Locust
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Load Test Runner"
echo "=========================================="

# Check if cluster is running
if ! kubectl get pods -n ml-benchmark >/dev/null 2>&1; then
    echo "❌ Kubernetes cluster not accessible. Run ./scripts/deploy-k8s.sh first."
    exit 1
fi

# Check pod status
echo "Checking pod status..."
kubectl get pods -n ml-benchmark

# Check if pods are ready
BENTOML_READY=$(kubectl get pods -n ml-benchmark -l app=bentoml-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
FASTAPI_READY=$(kubectl get pods -n ml-benchmark -l app=fastapi-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
RAYSERVE_READY=$(kubectl get pods -n ml-benchmark -l app=rayserve-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
LOCUST_READY=$(kubectl get pods -n ml-benchmark -l app=locust -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

echo ""
echo "Service Status:"
echo "  - BentoML: $BENTOML_READY"
echo "  - FastAPI: $FASTAPI_READY"
echo "  - Ray Serve: $RAYSERVE_READY"
echo "  - Locust:  $LOCUST_READY"

if [ "$LOCUST_READY" != "True" ]; then
    echo ""
    echo "⚠️  Locust is not ready yet. Waiting..."
    kubectl wait --for=condition=ready pod -l app=locust -n ml-benchmark --timeout=120s
fi

echo ""
echo "=========================================="
echo "Locust Web UI"
echo "=========================================="
echo ""
echo "Open http://localhost:8089 in your browser to start the load test."
echo ""
echo "Configuration suggestions:"
echo "  - Number of users: 50-100"
echo "  - Spawn rate: 5 users/second"
echo "  - Host: http://bentoml-mobilenet:3000 (for BentoML)"
echo "         http://fastapi-mobilenet:8000 (for FastAPI)"
echo "         http://rayserve-mobilenet:8000 (for Ray Serve)"
echo ""
echo "Press Ctrl+C to exit this script (services will keep running)"
echo ""

# Keep script running to show it's active
while true; do
    sleep 60
    echo "Load test services running... (Ctrl+C to exit)"
done
