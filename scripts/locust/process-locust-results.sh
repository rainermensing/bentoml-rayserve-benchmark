#!/bin/bash
# Process Locust Results Script
# Aggregates Locust CSV stats, generates charts and markdown report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
DATA_DIR="$PROJECT_DIR/tmp/locust"
REPORT_DIR="$PROJECT_DIR/reports/locust"
mkdir -p "$REPORT_DIR"

# Colors for output
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

main() {
    print_header "📊 Processing Locust Results"
    
    if [ ! -d "$DATA_DIR" ]; then
        echo "❌ Data directory $DATA_DIR not found."
        exit 1
    fi

    echo "📊 Generating Locust comparison report with charts..."
    uvx --with matplotlib --with numpy python3 "$SCRIPT_DIR/compare_locust.py" "$DATA_DIR" "$REPORT_DIR"

    echo ""
    echo "✅ Locust processing complete. Report is in $REPORT_DIR"
}

main "$@"
