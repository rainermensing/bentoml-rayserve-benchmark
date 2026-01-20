#!/bin/bash
# Automated Load Test Script - CLI Output
# Runs load tests against BentoML, FastAPI, and Ray Serve services and outputs results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TMP_DIR="$PROJECT_DIR/tmp/generic"
REPORT_DIR="$PROJECT_DIR/reports/generic"
mkdir -p "$TMP_DIR"
mkdir -p "$REPORT_DIR"

# Configuration
DURATION_PER_LEVEL=${1:-${DURATION_PER_LEVEL:-10}}  # Seconds to run each concurrency level
CONCURRENCY_LEVELS=${2:-${CONCURRENCY_LEVELS:-"10 20 40 80"}}  # Space-separated concurrency levels
REPLICAS=${3:-${REPLICAS:-1}} # Number of pods per service
SERVICE_FILTER=${4:-"all"} # Service to test: bentoml, fastapi, rayserve, or all

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check prerequisites
check_prerequisites() {
    print_header "🔍 Checking Prerequisites"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null;
    then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} kubectl available"
    
    # Check if kind is available
    if ! command -v kind &> /dev/null;
    then
        echo -e "${RED}❌ kind not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} kind available"
}

# Generate a sample image payload
generate_payload() {
    # Generate a real 224x224 JPEG image
    python3 -c "
import io
from PIL import Image
import numpy as np
img_array = np.random.randint(0, 256, (224, 224, 3), dtype=np.uint8)
img = Image.fromarray(img_array, 'RGB')
img.save('$TMP_DIR/test_image.jpg', format='JPEG')
" 2>/dev/null
}

# Run load test against a service (duration-based)
run_load_test() {
    local SERVICE_ID=$1    # e.g., "bentoml"
    local SERVICE_NAME=$2  # e.g., "BentoML"
    local SERVICE_URL=$3
    local HEALTH_PATH=${4:-/health}
    local CONCURRENT=$5
    local RESULTS_FILE="$TMP_DIR/loadtest_${SERVICE_ID}_${CONCURRENT}.txt"
    local START_TS=$(date +%s)
    
    print_subheader "Testing ${SERVICE_NAME} (Concurrency: ${CONCURRENT})"
    echo "  URL: ${SERVICE_URL}"
    echo "  Duration: ${DURATION_PER_LEVEL}s | Concurrency: ${CONCURRENT} | Pods: ${REPLICAS}"
    echo ""
    
    # Generate payload
    generate_payload
    local IMAGE_PATH="$TMP_DIR/test_image.jpg"
    
    # Health check first
    echo -n "  Health check: "
    local RETRIES=0
    local MAX_RETRIES=15
    local HEALTH_OK=false
    while [ $RETRIES -lt $MAX_RETRIES ]; do
        if curl -s --max-time 2 "${SERVICE_URL}${HEALTH_PATH}" > /dev/null 2>&1;
        then
            HEALTH_OK=true
            break
        fi
        echo -n "."
        sleep 5
        RETRIES=$((RETRIES + 1))
    done

    if [ "$HEALTH_OK" = true ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
    
    # Run the load test using curl in parallel
    echo "  Running load test..."
    
    # Create a temporary script for parallel execution
    cat > "$TMP_DIR/run_request.sh" << 'REQSCRIPT'
#!/bin/bash
URL=$1
IMAGE_PATH=$2
START=$(python3 -c "import time; print(time.time())")
RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 2 --max-time 8 -X POST "$URL/predict" \
    -F "files=@$IMAGE_PATH" 2>/dev/null)
END=$(python3 -c "import time; print(time.time())")
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
DURATION=$(python3 -c "print(round(($END - $START) * 1000, 2))")
if [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS $DURATION"
else
    echo "FAILED $DURATION"
fi
REQSCRIPT
    chmod +x "$TMP_DIR/run_request.sh"
    
    # Run requests for the specified duration
    > "$RESULTS_FILE"
    local END_AT=$(($(date +%s) + DURATION_PER_LEVEL))
    
    # Launch worker processes that run until time is up; track PIDs so we can force-stop
    WORKER_PIDS=()
    for i in $(seq 1 $CONCURRENT); do
        (
            while [ $(date +%s) -lt $END_AT ]; do
                "$TMP_DIR/run_request.sh" "$SERVICE_URL" "$IMAGE_PATH" >> "$RESULTS_FILE"
            done
        ) & 
        WORKER_PIDS+=($!)
    done
    
    # Show progress while waiting
    local ELAPSED=0
    while [ $ELAPSED -lt $DURATION_PER_LEVEL ]; do
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        local CURRENT_COUNT=$(wc -l < "$RESULTS_FILE" 2>/dev/null || echo "0")
        printf "\r  Progress: %ds/%ds (%d requests completed)" $ELAPSED $DURATION_PER_LEVEL $CURRENT_COUNT
    done
    
    # Stop any stragglers and wait
    for pid in "${WORKER_PIDS[@]}"; do
        kill $pid 2>/dev/null || true
    done

    # Ensure workers exit promptly
    for pid in "${WORKER_PIDS[@]}"; do
        wait $pid 2>/dev/null || true
    done

    local END_TS=$(date +%s)
    echo ""; echo "  Completed in $((END_TS-START_TS))s — parsing results..."
    
    # Parse results
    local SUCCESS=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
    local FAILED=$(grep -c "FAILED" "$RESULTS_FILE" 2>/dev/null || echo "0")
    
    # Ensure they are clean integers
    SUCCESS=${SUCCESS//[^0-9]/}
    FAILED=${FAILED//[^0-9]/}
    SUCCESS=${SUCCESS:-0}
    FAILED=${FAILED:-0}
    
    # Calculate statistics
    local STATS=$(python3 << PYSCRIPT
import statistics
import json

times = []
try:
    with open("$RESULTS_FILE", "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0] == "SUCCESS":
                times.append(float(parts[1]))
except Exception:
    pass

if times:
    avg = statistics.mean(times)
    median = statistics.median(times)
    min_t = min(times)
    max_t = max(times)
    times.sort()
    p95 = times[int(len(times) * 0.95)] if len(times) > 0 else times[0]
    p99 = times[int(len(times) * 0.99)] if len(times) > 0 else times[0]
    stdev = statistics.stdev(times) if len(times) > 1 else 0
    print(f"{avg:.2f},{median:.2f},{min_t:.2f},{max_t:.2f},{p95:.2f},{p99:.2f},{stdev:.2f}")
else:
    print("0,0,0,0,0,0,0")
PYSCRIPT
)
    
    IFS=',' read -r AVG MEDIAN MIN MAX P95 P99 STDEV <<< "$STATS"
    local RPS=$(python3 -c "print(round($SUCCESS / max($DURATION_PER_LEVEL, 0.001), 2))" 2>/dev/null || echo "0")
    local SUCCESS_RATE=$(python3 -c "print(round($SUCCESS / max($SUCCESS + $FAILED, 1) * 100, 1))" 2>/dev/null || echo "0")
    
    # Save to a JSON file for final aggregation
    cat > "$TMP_DIR/stats_${SERVICE_ID}_${CONCURRENT}.json" << EOF
{
    "rps": "$RPS",
    "avg": "$AVG",
    "median": "$MEDIAN",
    "min": "$MIN",
    "max": "$MAX",
    "p95": "$P95",
    "p99": "$P99",
    "success_rate": "$SUCCESS_RATE",
    "success": "$SUCCESS",
    "failed": "$FAILED"
}
EOF
}

# Main execution
main() {
    print_header "🚀 Automated Load Test - Sequential Cluster Mode"
    echo "  Duration per level: ${DURATION_PER_LEVEL}s"
    echo "  Concurrency levels: $CONCURRENCY_LEVELS"
    echo "  Pods per service:   $REPLICAS"
    echo "  Target service:     $SERVICE_FILTER"
    
    check_prerequisites
    
    # Only clear stats for the filtered service(s)
    if [ "$SERVICE_FILTER" = "all" ]; then
        rm -f "$TMP_DIR/stats_*.json"
    else
        rm -f "$TMP_DIR/stats_${SERVICE_FILTER}_*.json"
    fi
    
    for SVC in bentoml fastapi rayserve;
    do
        if [ "$SERVICE_FILTER" != "all" ] && [ "$SERVICE_FILTER" != "$SVC" ]; then
            continue
        fi

        print_header "🏗️  Service: $SVC"
        "$PROJECT_DIR/scripts/manage-service-cluster.sh" up "$SVC" "$REPLICAS"
        
        case $SVC in
            bentoml)  PORT=3000; SVC_PORT=3000; HEALTH="/healthz"; NAME="BentoML" ;;
            fastapi)  PORT=8000; SVC_PORT=8000; HEALTH="/health"; NAME="FastAPI" ;; 
            rayserve) PORT=31800; SVC_PORT=8000; HEALTH="/health"; NAME="Ray Serve" ;; 
        esac
        
        echo "🔌 Port forwarding..."
        pkill -f "kubectl port-forward.*$SVC-mobilenet.*$PORT" 2>/dev/null || true
        sleep 1
        kubectl port-forward svc/$SVC-mobilenet -n ml-benchmark $PORT:$SVC_PORT &>/dev/null &
        PF_PID=$!
        
        for CONCURRENT in $CONCURRENCY_LEVELS;
        do
            run_load_test "$SVC" "$NAME" "http://localhost:$PORT" "$HEALTH" "$CONCURRENT"
        done
        
        kill $PF_PID 2>/dev/null || true
        "$PROJECT_DIR/scripts/manage-service-cluster.sh" down "$SVC"
    done
    
    

    # Run data processing

    "$SCRIPT_DIR/process-results.sh" "$CONCURRENCY_LEVELS" "$DURATION_PER_LEVEL"
}



main "$@"