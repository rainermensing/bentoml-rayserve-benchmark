import json
import sys
import matplotlib.pyplot as plt
import numpy as np
import os

def generate_charts(results_json, output_dir):
    data = json.loads(results_json)
    
    concurrency = [str(r['concurrency']) for r in data]
    bentoml_rps = [float(r['bentoml_rps']) for r in data]
    fastapi_rps = [float(r['fastapi_rps']) for r in data]
    rayserve_rps = [float(r['rayserve_rps']) for r in data]
    
    bentoml_avg = [float(r['bentoml_avg']) for r in data]
    fastapi_avg = [float(r['fastapi_avg']) for r in data]
    rayserve_avg = [float(r['rayserve_avg']) for r in data]

    x = np.arange(len(concurrency))
    width = 0.25

    # RPS Chart
    plt.figure(figsize=(10, 6))
    plt.bar(x - width, bentoml_rps, width, label='BentoML', color='#00a2ff')
    plt.bar(x, fastapi_rps, width, label='FastAPI', color='#ff4b4b')
    plt.bar(x + width, rayserve_rps, width, label='Ray Serve', color='#ffa500')
    
    plt.xlabel('Concurrency')
    plt.ylabel('Requests per Second')
    plt.title('Throughput Comparison (Higher is better)')
    plt.xticks(x, concurrency)
    plt.legend()
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, 'throughput_comparison.png'))
    
    # Latency Chart
    plt.figure(figsize=(10, 6))
    plt.bar(x - width, bentoml_avg, width, label='BentoML', color='#00a2ff')
    plt.bar(x, fastapi_avg, width, label='FastAPI', color='#ff4b4b')
    plt.bar(x + width, rayserve_avg, width, label='Ray Serve', color='#ffa500')
    
    plt.xlabel('Concurrency')
    plt.ylabel('Average Latency (ms)')
    plt.title('Latency Comparison (Lower is better)')
    plt.xticks(x, concurrency)
    plt.legend()
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, 'latency_comparison.png'))
    
    print(f"Charts saved to {output_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python generate_charts.py '<json_data>' <output_dir>")
        sys.exit(1)
    generate_charts(sys.argv[1], sys.argv[2])
