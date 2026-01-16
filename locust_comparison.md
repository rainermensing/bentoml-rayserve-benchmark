# 📈 Locust Load Test Comparison

**Run Date:** 2026-01-16 17:17:39

## 📊 Visual Comparison
![Throughput](locust_throughput.png)
![Latency](locust_latency.png)

## 📊 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| Throughput (req/s) | 10.77 | 11.79 | 10.39 | **FastAPI** |
| Avg Latency (ms) | 66.59 | 70.45 | 77.92 | **BentoML** |
| P50 Latency (ms) | 63.00 | 56.00 | 71.00 | **FastAPI** |
| P95 Latency (ms) | 95.00 | 140.00 | 100.00 | **BentoML** |
| P99 Latency (ms) | 110.00 | 180.00 | 140.00 | **BentoML** |
| Total Requests | 42.00 | 46.00 | 41.00 | **FastAPI** |

## 📋 Detailed Results per Service

### BentoML
- **Requests:** 42 (0 failures)
- **RPS:** 10.77
- **Latency:** Avg: 66.59ms | P95: 95.00ms | P99: 110.00ms | Max: 110.69ms

### FastAPI
- **Requests:** 46 (0 failures)
- **RPS:** 11.79
- **Latency:** Avg: 70.45ms | P95: 140.00ms | P99: 180.00ms | Max: 180.13ms

### RayServe
- **Requests:** 41 (0 failures)
- **RPS:** 10.39
- **Latency:** Avg: 77.92ms | P95: 100.00ms | P99: 140.00ms | Max: 141.02ms