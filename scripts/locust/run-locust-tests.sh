#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
REPORT_DIR="$PROJECT_DIR/reports/locust"
DATA_DIR="$PROJECT_DIR/tmp/locust"
mkdir -p "$REPORT_DIR"
mkdir -p "$DATA_DIR"

DURATION=${1:-"30s"}
USERS=${2:-"10"}
SPAWN_RATE=${3:-"2"}

# Port forwarding
echo "🔌 Setting up port forwarding..."
pkill -f "kubectl port-forward.*ml-benchmark" || true
sleep 1

kubectl port-forward svc/bentoml-mobilenet -n ml-benchmark 3000:3000 &>/dev/null &
BENTOML_PF_PID=$!
kubectl port-forward svc/fastapi-mobilenet -n ml-benchmark 8000:8000 &>/dev/null &
FASTAPI_PF_PID=$!
kubectl port-forward svc/rayserve-mobilenet -n ml-benchmark 31800:8000 &>/dev/null &
RAYSERVE_PF_PID=$!

sleep 3
echo "✓ Port forwarding established"

cleanup() {
    echo "Cleaning up..."
    kill $BENTOML_PF_PID 2>/dev/null || true
    kill $FASTAPI_PF_PID 2>/dev/null || true
    kill $RAYSERVE_PF_PID 2>/dev/null || true
}
trap cleanup EXIT

run_locust() {
    local NAME=$1
    local URL=$2
    local REPORT_BASE="$DATA_DIR/${NAME}"
    local HTML_REPORT="${REPORT_BASE}_report.html"
    local CSV_PREFIX="${REPORT_BASE}_stats"
    
    echo "🚀 Running Locust for $NAME against $URL..."
    uvx --with numpy --with Pillow locust \
        -f "$SCRIPT_DIR/locustfile.py" \
        --headless \
        -u "$USERS" \
        -r "$SPAWN_RATE" \
        --run-time "$DURATION" \
        --host "$URL" \
        --html "$HTML_REPORT" \
        --csv "$CSV_PREFIX" \
        --only-summary
    
    echo "✓ $NAME reports generated (HTML & CSV) in $DATA_DIR"
}

run_locust "BentoML" "http://localhost:3000"
run_locust "FastAPI" "http://localhost:8000"
run_locust "RayServe" "http://localhost:31800"

echo "📊 Generating Locust comparison report with charts..."
uvx --with matplotlib --with numpy python3 "$SCRIPT_DIR/compare_locust.py" "$DATA_DIR" "$REPORT_DIR"

echo ""
echo "✅ All Locust tests complete. Report is in $REPORT_DIR (Data in $DATA_DIR)"
