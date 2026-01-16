# Automated Load Test Results

- Run timestamp: 2026-01-16T15:28:31
- Duration per level: s
- Concurrency levels: 
- Success criteria: HTTP 200

## Throughput (req/s)
| Concurrency | BentoML | FastAPI | Ray Serve |
| --- | --- | --- | --- |
| 1 | 3.60 | 3.80 | 3.40 |
| 5 | 16.20 | 17.10 | 12.50 |
| 10 | 21.00 | 17.50 | 20.40 |
| 20 | 23.20 | 17.30 | 21.30 |

## Latency (avg / p95 ms)
| Concurrency | BentoML avg | FastAPI avg | Ray Serve avg | BentoML p95 | FastAPI p95 | Ray Serve p95 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 140.97 | 142.59 | 157.53 | 249.29 | 401.71 | 184.26 |
| 5 | 146.26 | 143.81 | 227.33 | 203.59 | 206.20 | 250.36 |
| 10 | 247.87 | 391.40 | 309.30 | 326.23 | 439.90 | 449.84 |
| 20 | 520.86 | 942.13 | 664.94 | 684.68 | 1057.43 | 865.14 |

## Per-Concurrency Details
### Concurrency 1

- Throughput (req/s):
  - BentoML: 3.60 | FastAPI: 3.80 | Ray Serve: 3.40
- Latency avg (ms):
  - BentoML: 140.97 | FastAPI: 142.59 | Ray Serve: 157.53
- Latency p95 (ms):
  - BentoML: 249.29 | FastAPI: 401.71 | Ray Serve: 184.26

### Concurrency 5

- Throughput (req/s):
  - BentoML: 16.20 | FastAPI: 17.10 | Ray Serve: 12.50
- Latency avg (ms):
  - BentoML: 146.26 | FastAPI: 143.81 | Ray Serve: 227.33
- Latency p95 (ms):
  - BentoML: 203.59 | FastAPI: 206.20 | Ray Serve: 250.36

### Concurrency 10

- Throughput (req/s):
  - BentoML: 21.00 | FastAPI: 17.50 | Ray Serve: 20.40
- Latency avg (ms):
  - BentoML: 247.87 | FastAPI: 391.40 | Ray Serve: 309.30
- Latency p95 (ms):
  - BentoML: 326.23 | FastAPI: 439.90 | Ray Serve: 449.84

### Concurrency 20

- Throughput (req/s):
  - BentoML: 23.20 | FastAPI: 17.30 | Ray Serve: 21.30
- Latency avg (ms):
  - BentoML: 520.86 | FastAPI: 942.13 | Ray Serve: 664.94
- Latency p95 (ms):
  - BentoML: 684.68 | FastAPI: 1057.43 | Ray Serve: 865.14
