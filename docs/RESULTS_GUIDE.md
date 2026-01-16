# Interpreting Benchmark Results

## Key Metrics to Compare

### 1. Throughput (Requests per Second)
The most important metric for model serving performance.

| Metric | What it means |
|--------|--------------|
| RPS (avg) | Average requests handled per second |
| RPS (peak) | Maximum throughput during test |

**Higher is better.**

### 2. Latency (Response Time)

| Percentile | Meaning |
|------------|---------|
| p50 | Median response time (50% of requests faster) |
| p95 | 95% of requests complete within this time |
| p99 | 99% of requests complete within this time |
| Max | Worst-case response time |

**Lower is better.**

### 3. Error Rate

| Metric | Acceptable Range |
|--------|-----------------|
| Error rate | < 1% for production |
| Failed requests | Should be 0 under normal load |

### 4. Resource Utilization

| Resource | Healthy Range |
|----------|--------------|
| CPU | 60-80% under load |
| Memory | < 80% of limit |

## Sample Results Comparison

```
┌─────────────────┬──────────────┬──────────────┬──────────────┐
│ Metric          │ BentoML      │ FastAPI      │ Ray Serve    │
├─────────────────┼──────────────┼──────────────┼──────────────┤
│ RPS (avg)       │ 45.2         │ 42.8         │ 48.5         │
│ p50 latency     │ 95ms         │ 102ms        │ 90ms         │
│ p95 latency     │ 180ms        │ 195ms        │ 170ms        │
│ p99 latency     │ 250ms        │ 280ms        │ 240ms        │
│ Error rate      │ 0.02%        │ 0.01%        │ 0.02%        │
│ CPU (avg)       │ 72%          │ 75%          │ 78%          │
│ Memory (avg)    │ 1.8GB        │ 1.6GB        │ 2.1GB        │
└─────────────────┴──────────────┴──────────────┴──────────────┘
```

## What Affects Performance

### BentoML Advantages
- Built-in adaptive batching
- Optimized for ML workloads
- Native async support
- Prometheus metrics included

### FastAPI Advantages
- Simpler deployment
- Lower base memory footprint
- Familiar Python async patterns
- Flexible middleware options

### Ray Serve Advantages
- Scales out with Ray actors and replicas
- Built-in autoscaling and routing policies
- Works with distributed preprocessing pipelines
- HTTP ingress backed by FastAPI/Starlette

## Recommendations

1. **For high-throughput batch inference**: BentoML's adaptive batching typically provides better performance.

2. **For low-latency distributed scaling**: Ray Serve can deliver strong throughput with replica-based scaling and autoscaling.

3. **For simple single-request serving**: FastAPI is sufficient and easier to maintain.

4. **For production ML systems**: BentoML provides more ML-specific features (model versioning, runners, etc.).

5. **For mixed workloads and pipeline-style inference**: Ray Serve is a good fit when you need to chain preprocessing and model stages.

## Generating Comparison Charts

Use the included Python script to generate comparison charts:

```bash
cd loadtest/results
python ../analyze_results.py
```

This generates:
- `comparison_throughput.png`
- `comparison_latency.png`
- `comparison_summary.md`
