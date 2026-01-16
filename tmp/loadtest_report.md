# Automated Load Test Results

- Run timestamp: 2026-01-15T17:21:19
- Duration per level: s
- Concurrency levels: 
- Success criteria: HTTP 200

## Throughput (req/s)
| Concurrency | BentoML | FastAPI | Ray Serve |
| --- | --- | --- | --- |
| 1 | 0.00 | 2.90 | 2.70 |
| 5 | 0.00 | 13.10 | 12.50 |
| 10 | 0.00 | 16.50 | 18.10 |
| 20 | 0.00 | 15.60 | 18.10 |

## Latency (avg / p95 ms)
| Concurrency | BentoML avg | FastAPI avg | Ray Serve avg | BentoML p95 | FastAPI p95 | Ray Serve p95 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 701.38 | 158.04 | 189.13 | 6136.85 | 190.35 | 184.88 |
| 5 | 106.36 | 165.94 | 201.62 | 112.98 | 216.64 | 210.53 |
| 10 | 168.56 | 274.21 | 277.52 | 181.93 | 354.76 | 347.07 |
| 20 | 377.13 | 608.10 | 691.71 | 498.37 | 1127.65 | 883.78 |

## Per-Concurrency Details
### Concurrency 1

- Throughput (req/s):
  - BentoML: 0.00 | FastAPI: 2.90 | Ray Serve: 2.70
- Latency avg (ms):
  - BentoML: 701.38 | FastAPI: 158.04 | Ray Serve: 189.13
- Latency p95 (ms):
  - BentoML: 6136.85 | FastAPI: 190.35 | Ray Serve: 184.88

### Concurrency 5

- Throughput (req/s):
  - BentoML: 0.00 | FastAPI: 13.10 | Ray Serve: 12.50
- Latency avg (ms):
  - BentoML: 106.36 | FastAPI: 165.94 | Ray Serve: 201.62
- Latency p95 (ms):
  - BentoML: 112.98 | FastAPI: 216.64 | Ray Serve: 210.53

### Concurrency 10

- Throughput (req/s):
  - BentoML: 0.00 | FastAPI: 16.50 | Ray Serve: 18.10
- Latency avg (ms):
  - BentoML: 168.56 | FastAPI: 274.21 | Ray Serve: 277.52
- Latency p95 (ms):
  - BentoML: 181.93 | FastAPI: 354.76 | Ray Serve: 347.07

### Concurrency 20

- Throughput (req/s):
  - BentoML: 0.00 | FastAPI: 15.60 | Ray Serve: 18.10
- Latency avg (ms):
  - BentoML: 377.13 | FastAPI: 608.10 | Ray Serve: 691.71
- Latency p95 (ms):
  - BentoML: 498.37 | FastAPI: 1127.65 | Ray Serve: 883.78
