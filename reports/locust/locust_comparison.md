# 📈 Locust Load Test Comparison

**Run Date:** 2026-01-19 18:15:06

## 📊 Visual Comparison
![Throughput](locust_throughput.png)
![Latency](locust_latency.png)

## 📊 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| Throughput (req/s) | 42.96 | 21.81 | 33.31 | **BentoML** |
| Avg Latency (ms) | 473.61 | 1225.99 | 698.34 | **BentoML** |
| P50 Latency (ms) | 500.00 | 1400.00 | 770.00 | **BentoML** |
| P95 Latency (ms) | 710.00 | 1700.00 | 940.00 | **BentoML** |
| P99 Latency (ms) | 830.00 | 2200.00 | 990.00 | **BentoML** |
| Total Requests | 2538.00 | 1275.00 | 1970.00 | **BentoML** |

## 📋 Detailed Results per Service

### BentoML
- **Requests:** 2538 (0 failures)
- **RPS:** 42.96
- **Latency:** Avg: 473.61ms | P95: 710.00ms | P99: 830.00ms | Max: 970.91ms

### FastAPI
- **Requests:** 1275 (0 failures)
- **RPS:** 21.81
- **Latency:** Avg: 1225.99ms | P95: 1700.00ms | P99: 2200.00ms | Max: 6259.47ms

### RayServe
- **Requests:** 1970 (0 failures)
- **RPS:** 33.31
- **Latency:** Avg: 698.34ms | P95: 940.00ms | P99: 990.00ms | Max: 1056.14ms