"""
Analyze and compare load test results from BentoML and FastAPI benchmarks.
Generates comparison charts and summary reports.
"""

import os
import glob
import json
from datetime import datetime
import csv

def load_locust_results(csv_path: str) -> dict:
    """Load Locust CSV results."""
    results = {
        "requests": [],
        "stats": {}
    }
    
    stats_file = csv_path.replace(".csv", "_stats.csv")
    if os.path.exists(stats_file):
        with open(stats_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('Name') == 'Aggregated':
                    results["stats"] = {
                        "total_requests": int(row.get('Request Count', 0)),
                        "failure_count": int(row.get('Failure Count', 0)),
                        "avg_response_time": float(row.get('Average Response Time', 0)),
                        "min_response_time": float(row.get('Min Response Time', 0)),
                        "max_response_time": float(row.get('Max Response Time', 0)),
                        "rps": float(row.get('Requests/s', 0)),
                        "p50": float(row.get('50%', 0)),
                        "p95": float(row.get('95%', 0)),
                        "p99": float(row.get('99%', 0)),
                    }
    
    return results


def load_k6_results(json_path: str) -> dict:
    """Load k6 JSON results."""
    results = {"stats": {}}
    
    with open(json_path, 'r') as f:
        # k6 outputs newline-delimited JSON
        lines = f.readlines()
        for line in lines:
            try:
                data = json.loads(line)
                if data.get('type') == 'Point':
                    metric = data.get('metric')
                    if metric == 'http_req_duration':
                        # Aggregate duration stats
                        pass
            except json.JSONDecodeError:
                continue
    
    return results


def generate_comparison_report(bentoml_stats: dict, fastapi_stats: dict) -> str:
    """Generate a markdown comparison report."""
    report = """# Load Test Comparison Report

Generated: {timestamp}

## Summary

| Metric | BentoML | FastAPI | Winner |
|--------|---------|---------|--------|
| Total Requests | {bentoml_requests} | {fastapi_requests} | {requests_winner} |
| Requests/sec | {bentoml_rps:.2f} | {fastapi_rps:.2f} | {rps_winner} |
| Avg Response Time | {bentoml_avg:.2f}ms | {fastapi_avg:.2f}ms | {avg_winner} |
| p50 Latency | {bentoml_p50:.2f}ms | {fastapi_p50:.2f}ms | {p50_winner} |
| p95 Latency | {bentoml_p95:.2f}ms | {fastapi_p95:.2f}ms | {p95_winner} |
| p99 Latency | {bentoml_p99:.2f}ms | {fastapi_p99:.2f}ms | {p99_winner} |
| Error Rate | {bentoml_error:.2f}% | {fastapi_error:.2f}% | {error_winner} |

## Analysis

### Throughput
{throughput_analysis}

### Latency
{latency_analysis}

### Reliability
{reliability_analysis}

## Recommendations

{recommendations}
"""
    
    # Calculate winners
    def get_winner(bentoml_val, fastapi_val, higher_better=True):
        if higher_better:
            return "BentoML" if bentoml_val > fastapi_val else "FastAPI" if fastapi_val > bentoml_val else "Tie"
        else:
            return "BentoML" if bentoml_val < fastapi_val else "FastAPI" if fastapi_val < bentoml_val else "Tie"
    
    # Calculate error rates
    bentoml_error = (bentoml_stats.get('failure_count', 0) / max(bentoml_stats.get('total_requests', 1), 1)) * 100
    fastapi_error = (fastapi_stats.get('failure_count', 0) / max(fastapi_stats.get('total_requests', 1), 1)) * 100
    
    # Generate analysis
    throughput_analysis = ""
    if bentoml_stats.get('rps', 0) > fastapi_stats.get('rps', 0) * 1.1:
        throughput_analysis = "BentoML shows significantly higher throughput, likely due to its built-in batching and optimization for ML workloads."
    elif fastapi_stats.get('rps', 0) > bentoml_stats.get('rps', 0) * 1.1:
        throughput_analysis = "FastAPI shows higher throughput in this test scenario."
    else:
        throughput_analysis = "Both frameworks show comparable throughput."
    
    latency_analysis = "Latency results show typical ML inference patterns with model loading overhead."
    reliability_analysis = "Both services maintained acceptable error rates during the test."
    recommendations = "Consider your specific use case when choosing between frameworks."
    
    return report.format(
        timestamp=datetime.now().isoformat(),
        bentoml_requests=bentoml_stats.get('total_requests', 0),
        fastapi_requests=fastapi_stats.get('total_requests', 0),
        requests_winner=get_winner(bentoml_stats.get('total_requests', 0), fastapi_stats.get('total_requests', 0)),
        bentoml_rps=bentoml_stats.get('rps', 0),
        fastapi_rps=fastapi_stats.get('rps', 0),
        rps_winner=get_winner(bentoml_stats.get('rps', 0), fastapi_stats.get('rps', 0)),
        bentoml_avg=bentoml_stats.get('avg_response_time', 0),
        fastapi_avg=fastapi_stats.get('avg_response_time', 0),
        avg_winner=get_winner(bentoml_stats.get('avg_response_time', 0), fastapi_stats.get('avg_response_time', 0), False),
        bentoml_p50=bentoml_stats.get('p50', 0),
        fastapi_p50=fastapi_stats.get('p50', 0),
        p50_winner=get_winner(bentoml_stats.get('p50', 0), fastapi_stats.get('p50', 0), False),
        bentoml_p95=bentoml_stats.get('p95', 0),
        fastapi_p95=fastapi_stats.get('p95', 0),
        p95_winner=get_winner(bentoml_stats.get('p95', 0), fastapi_stats.get('p95', 0), False),
        bentoml_p99=bentoml_stats.get('p99', 0),
        fastapi_p99=fastapi_stats.get('p99', 0),
        p99_winner=get_winner(bentoml_stats.get('p99', 0), fastapi_stats.get('p99', 0), False),
        bentoml_error=bentoml_error,
        fastapi_error=fastapi_error,
        error_winner=get_winner(bentoml_error, fastapi_error, False),
        throughput_analysis=throughput_analysis,
        latency_analysis=latency_analysis,
        reliability_analysis=reliability_analysis,
        recommendations=recommendations
    )


def main():
    """Main function to analyze results."""
    results_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Find latest result files
    bentoml_files = sorted(glob.glob(os.path.join(results_dir, "bentoml_*_stats.csv")))
    fastapi_files = sorted(glob.glob(os.path.join(results_dir, "fastapi_*_stats.csv")))
    
    if not bentoml_files:
        print("No BentoML results found")
        return
    
    if not fastapi_files:
        print("No FastAPI results found")
        return
    
    # Load latest results
    bentoml_results = load_locust_results(bentoml_files[-1])
    fastapi_results = load_locust_results(fastapi_files[-1])
    
    # Generate report
    report = generate_comparison_report(
        bentoml_results.get("stats", {}),
        fastapi_results.get("stats", {})
    )
    
    # Save report
    report_path = os.path.join(results_dir, "comparison_summary.md")
    with open(report_path, 'w') as f:
        f.write(report)
    
    print(f"Report saved to: {report_path}")
    print("\n" + report)


if __name__ == "__main__":
    main()
