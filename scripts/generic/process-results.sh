#!/bin/bash
# Process Results Script
# Aggregates individual JSON stats, generates charts and markdown report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TMP_DIR="$PROJECT_DIR/tmp/generic"
REPORT_DIR="$PROJECT_DIR/reports/generic"
mkdir -p "$REPORT_DIR"

# Configuration
CONCURRENCY_LEVELS=${1:-${CONCURRENCY_LEVELS:-"10 20 40 80"}}
DURATION_PER_LEVEL=${2:-${DURATION_PER_LEVEL:-10}}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

# Aggregate results
aggregate_results() {
    # We use a temp script to avoid shell expansion issues
    cat << 'PYSCRIPT' > "$TMP_DIR/aggregate.py"
import json
import os
import sys

results = []
tmp_dir = sys.argv[1]
levels = sys.argv[2].split()

for concurrent in levels:
    level_data = {"concurrency": int(concurrent)}
    for svc in ["bentoml", "fastapi", "rayserve"]:
        stats_file = os.path.join(tmp_dir, f"stats_{svc}_{concurrent}.json")
        if os.path.exists(stats_file):
            try:
                with open(stats_file, "r") as f:
                    data = json.load(f)
                    level_data[f"{svc}_rps"] = data.get("rps", "0")
                    level_data[f"{svc}_avg"] = data.get("avg", "0")
                    level_data[f"{svc}_p95"] = data.get("p95", "0")
            except Exception:
                level_data[f"{svc}_rps"] = "0"
                level_data[f"{svc}_avg"] = "0"
                level_data[f"{svc}_p95"] = "0"
        else:
            level_data[f"{svc}_rps"] = "0"
            level_data[f"{svc}_avg"] = "0"
            level_data[f"{svc}_p95"] = "0"
    results.append(level_data)

print(json.dumps(results))
PYSCRIPT
    ALL_RESULTS=$(python3 "$TMP_DIR/aggregate.py" "$TMP_DIR" "$CONCURRENCY_LEVELS")
    export ALL_RESULTS
    rm "$TMP_DIR/aggregate.py"
}

# Print multi-level summary
print_multi_level_summary() {
    print_header "📈 Multi-Concurrency Results Summary"
    
    python3 << PYFINAL
import json
import os

all_results = json.loads(os.environ.get("ALL_RESULTS", "[]"))
if not all_results:
    print("No results to display.")
    exit(0)

print("")
print("  \033[1mThroughput by Concurrency:\033[0m")
print("  ─────────────────────────────────────────────────────────────────────────")
print(f"  {'Concurrency':>12} {'BentoML RPS':>14} {'FastAPI RPS':>14} {'Ray Serve RPS':>14}")
print("  ─────────────────────────────────────────────────────────────────────────")
for r in all_results:
    print(f"  {r['concurrency']:>12} {float(r.get('bentoml_rps', 0)):>14.2f} {float(r.get('fastapi_rps', 0)):>14.2f} {float(r.get('rayserve_rps', 0)):>14.2f}")

print("")
print("  \033[1mLatency (avg/p95) by Concurrency:\033[0m")
print("  ─────────────────────────────────────────────────────────────────────────")
print(f"  {'Concurrency':>12} {'BentoML avg':>14} {'FastAPI avg':>14} {'Ray Serve avg':>14} {'BentoML p95':>14} {'FastAPI p95':>14} {'Ray Serve p95':>14}")
print("  ─────────────────────────────────────────────────────────────────────────")
for r in all_results:
    print(
        f"  {r['concurrency']:>12} {float(r.get('bentoml_avg', 0)):>14.2f} {float(r.get('fastapi_avg', 0)):>14.2f} {float(r.get('rayserve_avg', 0)):>14.2f} "
        f"{float(r.get('bentoml_p95', 0)):>14.2f} {float(r.get('fastapi_p95', 0)):>14.2f} {float(r.get('rayserve_p95', 0)):>14.2f}")
PYFINAL
    echo ""
}

# Write a Markdown report
write_markdown_report() {
    local REPORT_PATH="$REPORT_DIR/loadtest_report.md"
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
    valid_values = dict((k, float(v)) for k, v in values.items() if v and float(v) > 0)
    if not valid_values:
        return "N/A"
    
    if lower_is_better:
        best_val = min(valid_values.values())
    else:
        best_val = max(valid_values.values())
    
    winners = [name for name, val in valid_values.items() if val == best_val]
    return "/".join(sorted(winners))

lines = [
    "# 📊 Benchmark Results: BentoML vs FastAPI vs Ray Serve",
    "",
    f"**Run Date:** {run_ts}",
    f"- **Duration per level:** {duration}s",
    f"- **Concurrency levels:** {levels}",
    "",
    "## 📈 Throughput Comparison (req/s)",
    "| Concurrency | BentoML | FastAPI | Ray Serve | Winner |"]

for r in results:
    t_vals = dict(BentoML=r.get("bentoml_rps"), FastAPI=r.get("fastapi_rps"), RayServe=r.get("rayserve_rps")) 
    winner = get_winner(t_vals, False)
    lines.append(f"| {r['concurrency']} | {fmt(r.get('bentoml_rps'))} | {fmt(r.get('fastapi_rps'))} | {fmt(r.get('rayserve_rps'))} | **{winner}** |")

lines.extend([
    "",
    "## ⏱️ Latency Comparison (Average ms)",
    "| Concurrency | BentoML | FastAPI | Ray Serve | Winner |"])

for r in results:
    l_vals = dict(BentoML=r.get("bentoml_avg"), FastAPI=r.get("fastapi_avg"), RayServe=r.get("rayserve_avg")) 
    winner = get_winner(l_vals, True)
    lines.append(f"| {r['concurrency']} | {fmt(r.get('bentoml_avg'))} | {fmt(r.get('fastapi_avg'))} | {fmt(r.get('rayserve_avg'))} | **{winner}** |")

lines.append("\n*Generated by Automated Benchmark Suite*")
with open(report_path, "w") as f:
    f.write("\n".join(lines))
PY
}

main() {
    aggregate_results
    print_multi_level_summary
    
    echo "📊 Generating charts..."
    uvx --with matplotlib --with numpy python3 "$SCRIPT_DIR/generate-charts.py" "$ALL_RESULTS" "$REPORT_DIR"
    
    write_markdown_report
    echo "📄 Markdown report saved to $REPORT_DIR/loadtest_report.md"
    print_header "✅ Processing Complete"
}

main "$@"