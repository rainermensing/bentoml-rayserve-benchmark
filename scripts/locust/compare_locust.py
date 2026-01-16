import csv
import os
import sys
from datetime import datetime
import matplotlib.pyplot as plt
import numpy as np

def parse_locust_stats(file_path):
    if not os.path.exists(file_path):
        return None
    with open(file_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get('Name') == 'Aggregated':
                try:
                    return {
                        'requests': int(row.get('Request Count', 0)),
                        'failures': int(row.get('Failure Count', 0)),
                        'rps': float(row.get('Requests/s', 0)),
                        'avg': float(row.get('Average Response Time', 0)),
                        'p50': float(row.get('50%', 0)),
                        'p95': float(row.get('95%', 0)),
                        'p99': float(row.get('99%', 0)),
                        'max': float(row.get('Max Response Time', 0)),
                    }
                except (ValueError, TypeError):
                    continue
    return None

def generate_charts(results, output_dir):
    services = list(results.keys())
    if not services:
        return
    
    rps = [results[s]['rps'] for s in services]
    avg = [results[s]['avg'] for s in services]
    p95 = [results[s]['p95'] for s in services]
    
    x = np.arange(len(services))
    
    # RPS Chart
    plt.figure(figsize=(10, 5))
    plt.bar(services, rps, color=['#00a2ff', '#ff4b4b', '#ffa500'][:len(services)])
    plt.title('Locust Throughput (Requests/s)')
    plt.ylabel('RPS')
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, 'locust_throughput.png'))
    plt.close()
    
    # Latency Chart
    plt.figure(figsize=(10, 5))
    width = 0.35
    plt.bar(x - width/2, avg, width, label='Avg Latency', color='#4CAF50')
    plt.bar(x + width/2, p95, width, label='P95 Latency', color='#FF9800')
    plt.xticks(x, services)
    plt.title('Locust Latency Comparison (ms)')
    plt.ylabel('Latency (ms)')
    plt.legend()
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, 'locust_latency.png'))
    plt.close()

def generate_markdown(results, output_path):
    run_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# 📈 Locust Load Test Comparison",
        f"\n**Run Date:** {run_ts}",
        "\n## 📊 Visual Comparison",
        "![Throughput](locust_throughput.png)",
        "![Latency](locust_latency.png)",
        "\n## 📊 Aggregated Metrics",
        "\n| Metric | BentoML | FastAPI | Ray Serve | Winner |",
        "| :--- | :--- | :--- | :--- | :--- |"
    ]
    metrics = [
        ('Throughput (req/s)', 'rps', False),
        ('Avg Latency (ms)', 'avg', True),
        ('P50 Latency (ms)', 'p50', True),
        ('P95 Latency (ms)', 'p95', True),
        ('P99 Latency (ms)', 'p99', True),
        ('Total Requests', 'requests', False),
    ]
    for label, key, lower_better in metrics:
        v1 = results.get('BentoML', {}).get(key, 0)
        v2 = results.get('FastAPI', {}).get(key, 0)
        v3 = results.get('RayServe', {}).get(key, 0)
        vals = {'BentoML': v1, 'FastAPI': v2, 'RayServe': v3}
        valid_vals = {k: v for k, v in vals.items() if v > 0}
        winner = "N/A"
        if valid_vals:
            if lower_better:
                winner = min(valid_vals, key=valid_vals.get)
            else:
                winner = max(valid_vals, key=valid_vals.get)
        lines.append(f"| {label} | {v1:.2f} | {v2:.2f} | {v3:.2f} | **{winner}** |")
    lines.append("\n## 📋 Detailed Results per Service")
    for svc in ['BentoML', 'FastAPI', 'RayServe']:
        res = results.get(svc)
        if not res: continue
        lines.append(f"\n### {svc}")
        lines.append(f"- **Requests:** {res['requests']} ({res['failures']} failures)")
        lines.append(f"- **RPS:** {res['rps']:.2f}")
        lines.append(f"- **Latency:** Avg: {res['avg']:.2f}ms | P95: {res['p95']:.2f}ms | P99: {res['p99']:.2f}ms | Max: {res['max']:.2f}ms")
    with open(output_path, 'w') as f:
        f.write("\n".join(lines))

def main(data_dir, report_dir):
    results = {}
    for svc in ['BentoML', 'FastAPI', 'RayServe']:
        stats_file = os.path.join(data_dir, f"{svc}_stats_stats.csv")
        data = parse_locust_stats(stats_file)
        if data:
            results[svc] = data
    if results:
        generate_charts(results, report_dir)
        report_path = os.path.join(report_dir, "locust_comparison.md")
        generate_markdown(results, report_path)
        print(f"Unified Locust report with charts generated: {report_path}")
    else:
        print(f"No Locust stats found in {data_dir} to compare.")

if __name__ == "__main__":
    if len(sys.argv) > 2:
        main(sys.argv[1], sys.argv[2])
    elif len(sys.argv) > 1:
        main(sys.argv[1], sys.argv[1])
    else:
        main("tmp/locust", "reports/locust")