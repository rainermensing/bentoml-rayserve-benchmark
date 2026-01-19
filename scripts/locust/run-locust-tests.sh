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

DEPLOYMENTS=("bentoml-mobilenet" "fastapi-mobilenet" "rayserve-mobilenet")

cleanup() {
    echo "🧹 Cleaning up..."
    pkill -f "kubectl port-forward.*ml-benchmark" || true
}
trap cleanup EXIT

scale_cluster() {
    local TARGET=$1
    echo "⚖️  Isolating resources for $TARGET..."
    
    for DEPLOYMENT in "${DEPLOYMENTS[@]}"; do
        if [ "$DEPLOYMENT" == "$TARGET" ]; then
            kubectl scale deployment "$DEPLOYMENT" -n ml-benchmark --replicas=1 >/dev/null
        else
            kubectl scale deployment "$DEPLOYMENT" -n ml-benchmark --replicas=0 >/dev/null
        fi
    done

    echo "⏳ Waiting for $TARGET to be ready..."
    kubectl wait --for=condition=available deployment/"$TARGET" -n ml-benchmark --timeout=120s >/dev/null
    echo "✓ $TARGET is ready."
}

run_test_cycle() {
    local NAME=$1
    local DEPLOYMENT=$2
    local LOCAL_PORT=$3
    local TARGET_PORT=$4
    local URL="http://localhost:$LOCAL_PORT"
    
    local REPORT_BASE="$DATA_DIR/${NAME}"
    local HTML_REPORT="${REPORT_BASE}_report.html"
    local CSV_PREFIX="${REPORT_BASE}_stats"

    scale_cluster "$DEPLOYMENT"

    echo "🔌 Starting port forwarding for $NAME ($LOCAL_PORT:$TARGET_PORT)..."
    kubectl port-forward "svc/$DEPLOYMENT" -n ml-benchmark "$LOCAL_PORT:$TARGET_PORT" &>/dev/null &
    local PF_PID=$!
    
    # Give port-forward a moment to establish
    sleep 2

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
    
    echo "✓ $NAME test complete."
    
    # Kill the specific port forward
    kill "$PF_PID" 2>/dev/null || true
}

# Run tests sequentially with isolation
run_test_cycle "BentoML" "bentoml-mobilenet" "3000" "3000"
run_test_cycle "FastAPI" "fastapi-mobilenet" "8000" "8000"
run_test_cycle "RayServe" "rayserve-mobilenet" "31800" "8000"

echo "📊 Generating Locust comparison report with charts..."
uvx --with matplotlib --with numpy python3 "$SCRIPT_DIR/compare_locust.py" "$DATA_DIR" "$REPORT_DIR"

echo ""
echo "✅ All Locust tests complete. Report is in $REPORT_DIR (Data in $DATA_DIR)"
echo "   Note: Other services were scaled to 0 during each test to ensure resource isolation."
