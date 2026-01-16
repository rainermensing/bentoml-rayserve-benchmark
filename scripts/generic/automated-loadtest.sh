#!/bin/bash
# Automated Load Test Script - CLI Output
# Runs load tests against BentoML, FastAPI, and Ray Serve services and outputs results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TMP_DIR="$PROJECT_DIR/tmp"
mkdir -p "$TMP_DIR"

# Configuration
DURATION_PER_LEVEL=${DURATION_PER_LEVEL:-10}  # Seconds to run each concurrency level
CONCURRENCY_LEVELS=${CONCURRENCY_LEVELS:-"10 20 40 80"}  # Space-separated concurrency levels

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
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} kubectl available"
    
    # Check if cluster is accessible
    if ! kubectl get pods -n ml-benchmark &> /dev/null; then
        echo -e "${RED}❌ Cannot access ml-benchmark namespace${NC}"
        echo "  Run: kubectl apply -f kubernetes/"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Kubernetes cluster accessible"
    
    # Check if services are running
    BENTOML_READY=$(kubectl get pods -n ml-benchmark -l app=bentoml-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    FASTAPI_READY=$(kubectl get pods -n ml-benchmark -l app=fastapi-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    RAYSERVE_READY=$(kubectl get pods -n ml-benchmark -l app=rayserve-mobilenet -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    RUN_RAY=true
    
    if [ "$BENTOML_READY" != "True" ]; then
        echo -e "${YELLOW}⏳ Waiting for BentoML service...${NC}"
        kubectl wait --for=condition=ready pod -l app=bentoml-mobilenet -n ml-benchmark --timeout=120s
    fi
    echo -e "${GREEN}✓${NC} BentoML service ready"
    
    if [ "$FASTAPI_READY" != "True" ]; then
        echo -e "${YELLOW}⏳ Waiting for FastAPI service...${NC}"
        kubectl wait --for=condition=ready pod -l app=fastapi-mobilenet -n ml-benchmark --timeout=120s
    fi
    echo -e "${GREEN}✓${NC} FastAPI service ready"

    if [ "$RAYSERVE_READY" != "True" ]; then
        echo -e "${YELLOW}⚠️  Ray Serve not ready; skipping Ray in this run.${NC}"
        RUN_RAY=false
    fi
    if [ "$RUN_RAY" = true ]; then
        echo -e "${GREEN}✓${NC} Ray Serve service ready"
    fi
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
    local SERVICE_NAME=$1
    local SERVICE_URL=$2
    local HEALTH_PATH=${3:-/health}
    local RESULTS_FILE="$TMP_DIR/loadtest_${SERVICE_NAME}_${CONCURRENT}.txt"
    local START_TS=$(date +%s)
    
    print_subheader "Testing ${SERVICE_NAME}"
    echo "  URL: ${SERVICE_URL}"
    echo "  Duration: ${DURATION_PER_LEVEL}s | Concurrency: ${CONCURRENT}"
    echo ""
    
    # Generate payload
    generate_payload
    local IMAGE_PATH="$TMP_DIR/test_image.jpg"
    
    # Health check first
    echo -n "  Health check: "
    if curl -s --max-time 5 "${SERVICE_URL}${HEALTH_PATH}" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        return 1
    fi
    
    # Run the load test using curl in parallel
    echo "  Running load test..."
    
    local START_TIME=$(python3 -c "import time; print(time.time())")
    local SUCCESS=0
    local FAILED=0
    
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
    local COMPLETED=0
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

    # Ensure workers exit promptly; hard-kill if they linger
    for pid in "${WORKER_PIDS[@]}"; do
        for _ in $(seq 1 10); do
            if ! kill -0 $pid 2>/dev/null; then
                break
            fi
            sleep 0.2
        done
        if kill -0 $pid 2>/dev/null; then
            kill -9 $pid 2>/dev/null || true
        fi
    done

    if [ ${#WORKER_PIDS[@]} -gt 0 ]; then
        wait "${WORKER_PIDS[@]}" 2>/dev/null || true
    fi

    local END_TS=$(date +%s)
    echo ""; echo "  Completed ${SERVICE_NAME} in $((END_TS-START_TS))s — parsing results..."
    echo ""
    
    local END_TIME=$(python3 -c "import time; print(time.time())")
    local TOTAL_DURATION=$DURATION_PER_LEVEL
    
    # Parse results
    SUCCESS=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
    FAILED=$(grep -c "FAILED" "$RESULTS_FILE" 2>/dev/null || echo "0")
    # Ensure they're clean integers
    SUCCESS=${SUCCESS//[^0-9]/}
    FAILED=${FAILED//[^0-9]/}
    SUCCESS=${SUCCESS:-0}
    FAILED=${FAILED:-0}
    
    # Calculate statistics
    local STATS=$(python3 << PYSCRIPT
import statistics

times = []
with open("$RESULTS_FILE", "r") as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) >= 2:
            times.append(float(parts[1]))

if times:
    avg = statistics.mean(times)
    median = statistics.median(times)
    min_t = min(times)
    max_t = max(times)
    if len(times) > 1:
        p95 = sorted(times)[int(len(times) * 0.95)]
        p99 = sorted(times)[int(len(times) * 0.99)]
        stdev = statistics.stdev(times)
    else:
        p95 = times[0]
        p99 = times[0]
        stdev = 0
    print(f"{avg:.2f},{median:.2f},{min_t:.2f},{max_t:.2f},{p95:.2f},{p99:.2f},{stdev:.2f}")
else:
    print("0,0,0,0,0,0,0")
PYSCRIPT
)
    
    IFS=',' read -r AVG MEDIAN MIN MAX P95 P99 STDEV <<< "$STATS"
    local RPS=$(python3 -c "print(round($SUCCESS / max($TOTAL_DURATION, 0.001), 2))" 2>/dev/null || echo "0")
    local SUCCESS_RATE=$(python3 -c "print(round($SUCCESS / max($SUCCESS + $FAILED, 1) * 100, 1))" 2>/dev/null || echo "0")
    
    # Set defaults if empty
    AVG=${AVG:-0}
    MEDIAN=${MEDIAN:-0}
    MIN=${MIN:-0}
    MAX=${MAX:-0}
    P95=${P95:-0}
    P99=${P99:-0}
    
    # Store results for comparison (using export for global scope)
    export "${SERVICE_NAME}_SUCCESS"="$SUCCESS"
    export "${SERVICE_NAME}_FAILED"="$FAILED"
    export "${SERVICE_NAME}_AVG"="$AVG"
    export "${SERVICE_NAME}_MEDIAN"="$MEDIAN"
    export "${SERVICE_NAME}_MIN"="$MIN"
    export "${SERVICE_NAME}_MAX"="$MAX"
    export "${SERVICE_NAME}_P95"="$P95"
    export "${SERVICE_NAME}_P99"="$P99"
    export "${SERVICE_NAME}_RPS"="$RPS"
    export "${SERVICE_NAME}_DURATION"="$TOTAL_DURATION"
    export "${SERVICE_NAME}_SUCCESS_RATE"="$SUCCESS_RATE"
    
    # Print results
    echo ""
    echo -e "  ${BOLD}Results:${NC}"
    echo -e "  ├─ Requests:     ${GREEN}$SUCCESS succeeded${NC}, ${RED}$FAILED failed${NC} (${SUCCESS_RATE}% success)"
    echo -e "  ├─ Duration:     ${TOTAL_DURATION}s"
    echo -e "  ├─ Throughput:   ${CYAN}${RPS} req/s${NC}"
    echo -e "  ├─ Latency Avg:  ${AVG}ms"
    echo -e "  ├─ Latency Med:  ${MEDIAN}ms"
    echo -e "  ├─ Latency Min:  ${MIN}ms"
    echo -e "  ├─ Latency Max:  ${MAX}ms"
    echo -e "  ├─ Latency P95:  ${YELLOW}${P95}ms${NC}"
    echo -e "  └─ Latency P99:  ${YELLOW}${P99}ms${NC}"
}

# Print comparison
print_comparison() {
    print_header "📊 Comparison Summary"
    
    echo ""
    printf "  ${BOLD}%-20s %15s %15s %15s %15s${NC}\n" "Metric" "BentoML" "FastAPI" "Ray Serve" "Winner"
    echo "  ─────────────────────────────────────────────────────────────────────────"
    compare_metric() {
        local METRIC=$1
        local BENTOML_VAL=${2:-0}
        local FASTAPI_VAL=${3:-0}
        local RAYSERVE_VAL=${4:-0}
        local LOWER_BETTER=$5  # 1 if lower is better (latency), 0 if higher is better (throughput)

        local WINNER=$(python3 - << PYWINNER
values = {
    'BentoML': float('${BENTOML_VAL}' or 0),
    'FastAPI': float('${FASTAPI_VAL}' or 0),
    'Ray Serve': float('${RAYSERVE_VAL}' or 0),
}
lower = ${LOWER_BETTER}
if lower:
    best_val = min(values.values())
else:
    best_val = max(values.values())

winners = [name for name, val in values.items() if val == best_val]
print('/'.join(sorted(winners)))
PYWINNER
)

        local WINNER_COLORED="$WINNER"
        if [ "$WINNER" != "Tie" ]; then
            WINNER_COLORED="${GREEN}${WINNER}${NC}"
        fi

        printf "  %-20s %15s %15s %15s %15b\n" "$METRIC" "$BENTOML_VAL" "$FASTAPI_VAL" "$RAYSERVE_VAL" "$WINNER_COLORED"
    }

    compare_metric "Throughput (req/s)" "${BENTOML_RPS:-0}" "${FASTAPI_RPS:-0}" "${RAYSERVE_RPS:-0}" 0
    compare_metric "Avg Latency (ms)" "${BENTOML_AVG:-0}" "${FASTAPI_AVG:-0}" "${RAYSERVE_AVG:-0}" 1
    compare_metric "Median Latency (ms)" "${BENTOML_MEDIAN:-0}" "${FASTAPI_MEDIAN:-0}" "${RAYSERVE_MEDIAN:-0}" 1
    compare_metric "P95 Latency (ms)" "${BENTOML_P95:-0}" "${FASTAPI_P95:-0}" "${RAYSERVE_P95:-0}" 1
    compare_metric "P99 Latency (ms)" "${BENTOML_P99:-0}" "${FASTAPI_P99:-0}" "${RAYSERVE_P99:-0}" 1
    compare_metric "Success Rate (%)" "${BENTOML_SUCCESS_RATE:-0}" "${FASTAPI_SUCCESS_RATE:-0}" "${RAYSERVE_SUCCESS_RATE:-0}" 0
    
    echo ""
    
    # Calculate overall performance difference
    echo -e "  ${BOLD}Summary:${NC}"
    python3 << PYSUMMARY
services = {
    "BentoML": {"avg": float("${BENTOML_AVG:-0}" or 0), "rps": float("${BENTOML_RPS:-0}" or 0)},
    "FastAPI": {"avg": float("${FASTAPI_AVG:-0}" or 0), "rps": float("${FASTAPI_RPS:-0}" or 0)},
    "Ray Serve": {"avg": float("${RAYSERVE_AVG:-0}" or 0), "rps": float("${RAYSERVE_RPS:-0}" or 0)},
}

best_latency = min(services.items(), key=lambda kv: kv[1]["avg"])
best_rps = max(services.items(), key=lambda kv: kv[1]["rps"])

print(f"  • Lowest avg latency: \033[0;32m{best_latency[0]}\033[0m ({best_latency[1]['avg']} ms)")
print(f"  • Highest throughput: \033[0;32m{best_rps[0]}\033[0m ({best_rps[1]['rps']} req/s)")
PYSUMMARY
    echo ""
}

# Print final multi-level summary
print_multi_level_summary() {
    print_header "📈 Multi-Concurrency Results Summary"
    
    python3 << PYFINAL
import json

# Load all results
results = json.loads('''$ALL_RESULTS''')
avg_lat_improvement = sum((float(r['fastapi_avg']) - float(r['bentoml_avg'])) / max(float(r['fastapi_avg']), 0.001) * 100 for r in results) / len(results)
print("")
print("  \033[1mThroughput by Concurrency:\033[0m")
print("  ─────────────────────────────────────────────────────────────────────────")
print(f"  {'Concurrency':>12} {'BentoML RPS':>14} {'FastAPI RPS':>14} {'Ray Serve RPS':>14}")
print("  ─────────────────────────────────────────────────────────────────────────")
for r in results:
    print(f"  {r['concurrency']:>12} {float(r['bentoml_rps']):>14.2f} {float(r['fastapi_rps']):>14.2f} {float(r.get('rayserve_rps', 0)):>14.2f}")

print("")
print("  \033[1mLatency (avg/p95) by Concurrency:\033[0m")
print("  ─────────────────────────────────────────────────────────────────────────")
print(f"  {'Concurrency':>12} {'BentoML avg':>14} {'FastAPI avg':>14} {'Ray Serve avg':>14} {'BentoML p95':>14} {'FastAPI p95':>14} {'Ray Serve p95':>14}")
print("  ─────────────────────────────────────────────────────────────────────────")
for r in results:
    print(
        f"  {r['concurrency']:>12} {float(r['bentoml_avg']):>14.2f} {float(r['fastapi_avg']):>14.2f} {float(r.get('rayserve_avg', 0)):>14.2f} "
        f"{float(r['bentoml_p95']):>14.2f} {float(r['fastapi_p95']):>14.2f} {float(r.get('rayserve_p95', 0)):>14.2f}"
    )

print("")
print("  \033[1mWinners by Concurrency (lower latency / higher throughput):\033[0m")
print("  ─────────────────────────────────────────────────────────────────────────")
print(f"  {'Concurrency':>12} {'Latency Winner':>18} {'Throughput Winner':>22}")
print("  ─────────────────────────────────────────────────────────────────────────")
for r in results:
    latency_values = {
        'BentoML': float(r['bentoml_avg']),
        'FastAPI': float(r['fastapi_avg']),
        'Ray Serve': float(r.get('rayserve_avg', 0)),
    }
    throughput_values = {
        'BentoML': float(r['bentoml_rps']),
        'FastAPI': float(r['fastapi_rps']),
        'Ray Serve': float(r.get('rayserve_rps', 0)),
    }
    best_latency = min(latency_values.items(), key=lambda kv: kv[1])
    best_rps = max(throughput_values.items(), key=lambda kv: kv[1])
    print(f"  {r['concurrency']:>12} {best_latency[0]:>18} {best_rps[0]:>22}")

print("")
print("  \033[1mOverall Summary:\033[0m")
latency_wins = {'BentoML': 0, 'FastAPI': 0, 'Ray Serve': 0}
throughput_wins = {'BentoML': 0, 'FastAPI': 0, 'Ray Serve': 0}
for r in results:
    latency_values = {
        'BentoML': float(r['bentoml_avg']),
        'FastAPI': float(r['fastapi_avg']),
        'Ray Serve': float(r.get('rayserve_avg', 0)),
    }
    throughput_values = {
        'BentoML': float(r['bentoml_rps']),
        'FastAPI': float(r['fastapi_rps']),
        'Ray Serve': float(r.get('rayserve_rps', 0)),
    }
    latency_wins[min(latency_values, key=latency_values.get)] += 1
    throughput_wins[max(throughput_values, key=throughput_values.get)] += 1

for svc, wins in latency_wins.items():
    print(f"  • {svc} had the lowest latency in {wins}/{len(results)} levels")
for svc, wins in throughput_wins.items():
    print(f"  • {svc} had the highest throughput in {wins}/{len(results)} levels")
PYFINAL
    echo ""
}

# Write a Markdown report to the project tmp directory
write_markdown_report() {
    local REPORT_PATH="$TMP_DIR/loadtest_report.md"
    REPORT_PATH="$REPORT_PATH" python3 << 'PY'
import json
import os
import datetime

report_path = os.environ["REPORT_PATH"]
results = json.loads(os.environ.get("ALL_RESULTS", "[]"))
duration = os.environ.get("DURATION_PER_LEVEL", "")
levels = os.environ.get("CONCURRENCY_LEVELS", "")
run_ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def fmt(val):
    try:
        v = float(val)
        return f"{v:.2f}"
    except (ValueError, TypeError):
        return "0.00"

def get_winner(values, lower_is_better=True):
    valid_values = {k: float(v) for k, v in values.items() if v and float(v) > 0}
    if not valid_values:
        return "N/A"
    if lower_is_better:
        winner = min(valid_values, key=valid_values.get)
    else:
        winner = max(valid_values, key=valid_values.get)
    return winner

lines = [
    "# 📊 Benchmark Results: BentoML vs FastAPI vs Ray Serve",
    "",
    f"**Run Date:** {run_ts}",
    f"- **Duration per level:** {duration}s",
    f"- **Concurrency levels:** {levels}",
    "",
    "## 🏆 Executive Summary",
    "",
]

if not results:
    lines.append("_No results recorded._")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(report_path)
    raise SystemExit

# Add Charts
lines.append("## 📊 Visual Comparison")
lines.append("![Throughput Comparison](throughput_comparison.png)")
lines.append("![Latency Comparison](latency_comparison.png)")
lines.append("")

# Overall Winners
latency_wins = {"BentoML": 0, "FastAPI": 0, "Ray Serve": 0}
throughput_wins = {"BentoML": 0, "FastAPI": 0, "Ray Serve": 0}

for r in results:
    l_vals = {"BentoML": r.get("bentoml_avg"), "FastAPI": r.get("fastapi_avg"), "Ray Serve": r.get("rayserve_avg")}
    t_vals = {"BentoML": r.get("bentoml_rps"), "FastAPI": r.get("fastapi_rps"), "Ray Serve": r.get("rayserve_rps")}
    
    l_winner = get_winner(l_vals, True)
    if l_winner in latency_wins: latency_wins[l_winner] += 1
    
    t_winner = get_winner(t_vals, False)
    if t_winner in throughput_wins: throughput_wins[t_winner] += 1

best_latency = max(latency_wins, key=latency_wins.get)
best_throughput = max(throughput_wins, key=throughput_wins.get)

lines.append(f"- **Latency King:** {best_latency} (won {latency_wins[best_latency]}/{len(results)} levels)")
lines.append(f"- **Throughput King:** {best_throughput} (won {throughput_wins[best_throughput]}/{len(results)} levels)")
lines.append("")

lines.append("## 📈 Throughput Comparison (req/s)")
lines.append("| Concurrency | BentoML | FastAPI | Ray Serve | Winner |")
lines.append("| :--- | :--- | :--- | :--- | :--- |")
for r in results:
    t_vals = {"BentoML": r.get("bentoml_rps"), "FastAPI": r.get("fastapi_rps"), "Ray Serve": r.get("rayserve_rps")}
    winner = get_winner(t_vals, False)
    lines.append(
        f"| {r['concurrency']} | {fmt(r.get('bentoml_rps'))} | {fmt(r.get('fastapi_rps'))} | {fmt(r.get('rayserve_rps'))} | **{winner}** |"
    )

lines.append("")
lines.append("## ⏱️ Latency Comparison (Average ms)")
lines.append("| Concurrency | BentoML | FastAPI | Ray Serve | Winner |")
lines.append("| :--- | :--- | :--- | :--- | :--- |")
for r in results:
    l_vals = {"BentoML": r.get("bentoml_avg"), "FastAPI": r.get("fastapi_avg"), "Ray Serve": r.get("rayserve_avg")}
    winner = get_winner(l_vals, True)
    lines.append(
        f"| {r['concurrency']} | {fmt(r.get('bentoml_avg'))} | {fmt(r.get('fastapi_avg'))} | {fmt(r.get('rayserve_avg'))} | **{winner}** |"
    )

lines.append("")
lines.append("## 🎯 P95 Latency Comparison (ms)")
lines.append("| Concurrency | BentoML | FastAPI | Ray Serve | Winner |")
lines.append("| :--- | :--- | :--- | :--- | :--- |")
for r in results:
    p95_vals = {"BentoML": r.get("bentoml_p95"), "FastAPI": r.get("fastapi_p95"), "Ray Serve": r.get("rayserve_p95")}
    winner = get_winner(p95_vals, True)
    lines.append(
        f"| {r['concurrency']} | {fmt(r.get('bentoml_p95'))} | {fmt(r.get('fastapi_p95'))} | {fmt(r.get('rayserve_p95'))} | **{winner}** |"
    )

lines.append("")
lines.append("---")
lines.append("*Generated by Automated Benchmark Suite*")

with open(report_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

# Also save to root directory
root_report_path = os.path.join(os.path.dirname(os.path.dirname(report_path)), "loadtest_report.md")
with open(root_report_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

    print(report_path)
PY
    echo "  Markdown report saved to: $REPORT_PATH and ./loadtest_report.md"
}
# Main execution
main() {
    print_header "🚀 Automated Load Test - BentoML vs FastAPI vs Ray Serve"
    echo ""
    echo "  Configuration:"
    echo "  • Duration per level: ${DURATION_PER_LEVEL}s"
    echo "  • Concurrency levels: $CONCURRENCY_LEVELS"
    
    check_prerequisites
    
    # Set up port forwarding if needed
    print_header "🔌 Setting Up Connections"
    
    # Kill existing port forwards
    pkill -f "kubectl port-forward.*bentoml-mobilenet.*3000:3000" 2>/dev/null || true
    pkill -f "kubectl port-forward.*fastapi-mobilenet.*8000:8000" 2>/dev/null || true
    pkill -f "kubectl port-forward.*rayserve-mobilenet.*31800:8000" 2>/dev/null || true
    sleep 1
    
    # Start port forwarding
    kubectl port-forward svc/bentoml-mobilenet -n ml-benchmark 3000:3000 &>/dev/null &
    BENTOML_PF_PID=$!
    kubectl port-forward svc/fastapi-mobilenet -n ml-benchmark 8000:8000 &>/dev/null &
    FASTAPI_PF_PID=$!
    if [ "$RUN_RAY" = true ]; then
        kubectl port-forward svc/rayserve-mobilenet -n ml-benchmark 31800:8000 &>/dev/null &
        RAYSERVE_PF_PID=$!
    fi
    
    # Wait for port forwarding to be ready
    sleep 3
    echo -e "${GREEN}✓${NC} Port forwarding established"
    
    # Cleanup function
    cleanup() {
        echo ""
        echo "Cleaning up..."
        kill $BENTOML_PF_PID 2>/dev/null || true
        kill $FASTAPI_PF_PID 2>/dev/null || true
        if [ "$RUN_RAY" = true ]; then
            kill $RAYSERVE_PF_PID 2>/dev/null || true
        fi
        rm -f "$TMP_DIR/payload.json" "$TMP_DIR/run_request.sh" "$TMP_DIR"/loadtest_*.txt
    }
    trap cleanup EXIT
    
    # Initialize results array
    ALL_RESULTS="["
    FIRST_RESULT=true
    
    # Run tests at each concurrency level
    for CONCURRENT in $CONCURRENCY_LEVELS; do
        export CONCURRENT
        
        print_header "🧪 Testing with Concurrency: $CONCURRENT"
        
        # Test BentoML
        run_load_test "BENTOML" "http://localhost:3000" "/healthz"
        
        # Test FastAPI  
        run_load_test "FASTAPI" "http://localhost:8000" "/health"

        # Test Ray Serve (optional)
        if [ "$RUN_RAY" = true ]; then
            run_load_test "RAYSERVE" "http://localhost:31800" "/health"
        else
            export RAYSERVE_RPS=0
            export RAYSERVE_AVG=0
            export RAYSERVE_P95=0
            export RAYSERVE_SUCCESS_RATE=0
        fi
        
        # Store results for this level
        if [ "$FIRST_RESULT" = true ]; then
            FIRST_RESULT=false
        else
            ALL_RESULTS="$ALL_RESULTS,"
        fi
        
        ALL_RESULTS="$ALL_RESULTS{\"concurrency\": $CONCURRENT, \"bentoml_rps\": \"$BENTOML_RPS\", \"bentoml_avg\": \"$BENTOML_AVG\", \"bentoml_p95\": \"$BENTOML_P95\", \"bentoml_success\": \"$BENTOML_SUCCESS_RATE\", \"fastapi_rps\": \"$FASTAPI_RPS\", \"fastapi_avg\": \"$FASTAPI_AVG\", \"fastapi_p95\": \"$FASTAPI_P95\", \"fastapi_success\": \"$FASTAPI_SUCCESS_RATE\", \"rayserve_rps\": \"$RAYSERVE_RPS\", \"rayserve_avg\": \"$RAYSERVE_AVG\", \"rayserve_p95\": \"$RAYSERVE_P95\", \"rayserve_success\": \"$RAYSERVE_SUCCESS_RATE\"}"
        
        # Print quick comparison for this level
        print_comparison
    done
    
    ALL_RESULTS="$ALL_RESULTS]"
    export ALL_RESULTS
    
    # Print final multi-level summary
    print_multi_level_summary

    # Generate charts
    echo "📊 Generating comparison charts..."
    uvx --with matplotlib --with numpy python3 "$SCRIPT_DIR/generate-charts.py" "$ALL_RESULTS" "$TMP_DIR"

    # Write markdown report
    write_markdown_report
    
    print_header "✅ Load Test Complete"
    echo ""
    echo "  Results saved to: $TMP_DIR/loadtest_*.txt"
    echo "  Markdown report: $TMP_DIR/loadtest_report.md"
    echo ""
}

# Run main
main "$@"
