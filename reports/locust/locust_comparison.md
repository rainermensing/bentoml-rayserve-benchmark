# 📈 Locust Load Test Comparison

**Run Date:** 2026-01-19 16:44:47

## 📊 Visual Comparison
![Throughput](locust_throughput.png)
![Latency](locust_latency.png)

## 📊 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| Throughput (req/s) | 26.34 | 21.06 | 25.10 | **BentoML** |
| Avg Latency (ms) | 105.29 | 587.21 | 191.58 | **BentoML** |
| P50 Latency (ms) | 92.00 | 600.00 | 170.00 | **BentoML** |
| P95 Latency (ms) | 220.00 | 1300.00 | 410.00 | **BentoML** |
| P99 Latency (ms) | 320.00 | 1600.00 | 500.00 | **BentoML** |
| Total Requests | 1559.00 | 1238.00 | 1483.00 | **BentoML** |

## 📋 Detailed Results per Service

### BentoML
- **Requests:** 1559 (0 failures)
- **RPS:** 26.34
- **Latency:** Avg: 105.29ms | P95: 220.00ms | P99: 320.00ms | Max: 388.81ms

### FastAPI
- **Requests:** 1238 (0 failures)
- **RPS:** 21.06
- **Latency:** Avg: 587.21ms | P95: 1300.00ms | P99: 1600.00ms | Max: 3134.56ms

### RayServe
- **Requests:** 1483 (0 failures)
- **RPS:** 25.10
- **Latency:** Avg: 191.58ms | P95: 410.00ms | P99: 500.00ms | Max: 642.18ms