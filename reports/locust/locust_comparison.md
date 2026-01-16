# 📈 Locust Load Test Comparison

**Run Date:** 2026-01-16 18:18:28

## 📊 Visual Comparison
![Throughput](locust_throughput.png)
![Latency](locust_latency.png)

## 📊 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| Throughput (req/s) | 44.50 | 23.26 | 34.93 | **BentoML** |
| Avg Latency (ms) | 891.35 | 1942.87 | 1199.53 | **BentoML** |
| P50 Latency (ms) | 1000.00 | 2000.00 | 1400.00 | **BentoML** |
| P95 Latency (ms) | 1500.00 | 3100.00 | 1900.00 | **BentoML** |
| P99 Latency (ms) | 1600.00 | 6700.00 | 2100.00 | **BentoML** |
| Total Requests | 2628.00 | 1359.00 | 2063.00 | **BentoML** |

## 📋 Detailed Results per Service

### BentoML
- **Requests:** 2628 (0 failures)
- **RPS:** 44.50
- **Latency:** Avg: 891.35ms | P95: 1500.00ms | P99: 1600.00ms | Max: 1693.95ms

### FastAPI
- **Requests:** 1359 (0 failures)
- **RPS:** 23.26
- **Latency:** Avg: 1942.87ms | P95: 3100.00ms | P99: 6700.00ms | Max: 12382.36ms

### RayServe
- **Requests:** 2063 (0 failures)
- **RPS:** 34.93
- **Latency:** Avg: 1199.53ms | P95: 1900.00ms | P99: 2100.00ms | Max: 2176.09ms