# 📈 Locust Load Test Comparison

**Run Date:** 2026-01-20 13:06:53

## 📊 Visual Comparison
![Throughput](locust_throughput.png)
![Latency](locust_latency.png)

## 📊 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| Throughput (req/s) | 48.28 | 23.30 | 35.87 | **BentoML** |
| Avg Latency (ms) | 1058.71 | 1843.00 | 1514.13 | **BentoML** |
| P50 Latency (ms) | 1200.00 | 1500.00 | 1600.00 | **BentoML** |
| P95 Latency (ms) | 1700.00 | 3100.00 | 2400.00 | **BentoML** |
| P99 Latency (ms) | 1800.00 | 15000.00 | 2500.00 | **BentoML** |
| Total Requests | 2375.00 | 1129.00 | 1758.00 | **BentoML** |

## 📋 Detailed Results per Service

### BentoML
- **Requests:** 2375 (0 failures)
- **RPS:** 48.28
- **Latency:** Avg: 1058.71ms | P95: 1700.00ms | P99: 1800.00ms | Max: 1811.76ms

### FastAPI
- **Requests:** 1129 (0 failures)
- **RPS:** 23.30
- **Latency:** Avg: 1843.00ms | P95: 3100.00ms | P99: 15000.00ms | Max: 27360.16ms

### RayServe
- **Requests:** 1758 (0 failures)
- **RPS:** 35.87
- **Latency:** Avg: 1514.13ms | P95: 2400.00ms | P99: 2500.00ms | Max: 2556.69ms