#!/bin/bash
# Locust Load Test Script
# Runs Locust tests against BentoML, FastAPI, and Ray Serve services using sequential clusters

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
REPLICAS=${4:-1}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}── $1 ──${NC}"
}

run_test_cycle() {
    local SVC=$1
    local NAME=$2
    local PORT=$3
    local SVC_PORT=$4
    local HEALTH_PATH=$5
    local URL="http://localhost:$PORT"
    
    local REPORT_BASE="$DATA_DIR/${NAME}"
    local HTML_REPORT="${REPORT_BASE}_report.html"
    local CSV_PREFIX="${REPORT_BASE}_stats"

    print_header "🏗️  Service: $NAME"
    "$PROJECT_DIR/scripts/manage-service-cluster.sh" up "$SVC" "$REPLICAS"

    # Health check
    echo -n "🔌 Waiting for $NAME health check..."
    local RETRIES=0
    local MAX_RETRIES=20
    local HEALTH_OK=false
    
    # Need port-forward for health check
    kubectl port-forward svc/$SVC-mobilenet -n ml-benchmark $PORT:$SVC_PORT &>/dev/null &
    local PF_PID=$!
    sleep 2

    while [ $RETRIES -lt $MAX_RETRIES ]; do
        if curl -s --max-time 2 "${URL}${HEALTH_PATH}" > /dev/null 2>&1; then
            HEALTH_OK=true
            break
        fi
        echo -n "."
        sleep 5
        RETRIES=$((RETRIES + 1))
    done

    if [ "$HEALTH_OK" != true ]; then
        echo -e "${RED}FAILED${NC}"
        kill $PF_PID 2>/dev/null || true
        "$PROJECT_DIR/scripts/manage-service-cluster.sh" down "$SVC"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"

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
    
    kill "$PF_PID" 2>/dev/null || true
    "$PROJECT_DIR/scripts/manage-service-cluster.sh" down "$SVC"
}

# Main execution
print_header "🚀 Locust Load Test - Sequential Cluster Mode"
echo "  Duration:   $DURATION"
echo "  Users:      $USERS"
echo "  Spawn Rate: $SPAWN_RATE"
echo "  Replicas:   $REPLICAS"

# Clear old results
rm -f "$DATA_DIR"/*_stats*

# Run tests sequentially
run_test_cycle "bentoml" "BentoML" "3000" "3000" "/healthz"
run_test_cycle "fastapi" "FastAPI" "8000" "8000" "/health"
run_test_cycle "rayserve" "RayServe" "31800" "8000" "/health"

# Run data processing
"$SCRIPT_DIR/process-locust-results.sh"

echo ""
echo "✅ All Locust tests complete."