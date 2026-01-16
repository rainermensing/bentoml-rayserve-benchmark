# BentoML vs FastAPI vs Ray Serve Benchmark

A comprehensive load testing comparison between BentoML, FastAPI, and Ray Serve for serving TensorFlow models in Kubernetes using Kind.

## Overview

This benchmark compares the performance of three popular ML model serving frameworks:
- **BentoML**: A unified model serving framework with native Kubernetes support (pinned 1.4.33)
- **FastAPI**: A high-performance Python web framework with uvicorn
- **Ray Serve**: A distributed model serving framework built on Ray (pinned 2.53.0)

Both services use **MobileNetV2** (pre-trained on ImageNet) for image classification.

## Project Structure

```
.
├── README.md                    # This file
├── Makefile                     # Shortcut targets: setup, build, deploy, loadtest, cleanup
├── kind-config.yaml             # Kind cluster configuration
├── model/
│   ├── download_model.py        # Script to download MobileNetV2 model
│   └── requirements.txt         # Model download dependencies
├── bentoml/
│   ├── service.py               # BentoML service definition
│   ├── bentofile.yaml           # BentoML build configuration
│   └── requirements.txt         # BentoML service dependencies
├── fastapi/
│   ├── main.py                  # FastAPI service
│   ├── Dockerfile               # FastAPI container build
│   └── requirements.txt         # FastAPI dependencies
├── rayserve/
│   ├── app.py                   # Ray Serve deployment (FastAPI ingress)
│   ├── Dockerfile               # Ray Serve container build
│   └── requirements.txt         # Ray Serve dependencies
├── kubernetes/
│   ├── namespace.yaml           # ml-benchmark namespace
│   ├── bentoml-deployment.yaml  # BentoML deployment + service
│   ├── fastapi-deployment.yaml  # FastAPI deployment + service
│   ├── rayserve-deployment.yaml # Ray Serve deployment + service
│   └── locust-service-deployment.yaml # Locust deployment + service
├── locust_service/
│   ├── locustfile.py            # Locust load test definition
│   ├── k6-script.js             # k6 load test script (alternative)
│   ├── Dockerfile               # Locust service container build
│   └── analyze_results.py       # Results analysis script
├── scripts/
│   ├── setup.sh                 # Complete setup script
│   ├── build-images.sh          # Build Docker images (BentoML, FastAPI, Ray Serve, locust-service)
│   ├── deploy-k8s.sh            # Deploy to Kubernetes / Kind
│   ├── automated-loadtest.sh    # CLI load test (curl-based) + Markdown report
│   ├── test-containers.sh       # Run smoke tests on local Docker containers
│   └── cleanup.sh               # Cleanup resources
└── docs/
    ├── QUICKSTART.md            # Quick start guide
    └── RESULTS_GUIDE.md         # How to interpret results
```

## Prerequisites

- **Docker Desktop** (with at least 8GB RAM allocated)
- **Kind** (Kubernetes in Docker): `brew install kind`
- **kubectl**: `brew install kubectl`
- **uv** (fast Python package manager): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Python 3.10+**

## Quick Start

### Option 1: One-liners (Makefile)

```bash
make setup     # download model, build images, create Kind cluster, deploy
make loadtest  # run automated load test and emit Markdown report
make cleanup   # tear everything down
```

### Option 2: Scripted (fine-grained)

```bash
# 1) Download model
python model/download_model.py

# 2) Build all images (BentoML 1.4.33, Ray Serve 2.53.0)
./scripts/build-images.sh

# 3) Deploy to Kind
./scripts/deploy-k8s.sh

# 4) Run load test (curl-based, writes Markdown to tmp/loadtest_report.md)
./scripts/automated-loadtest.sh
```

## Accessing Services

After deployment, services are available at:

| Service | URL | Description |
|---------|-----|-------------|
| BentoML | http://localhost:3000 | MobileNetV2 classifier (BentoML) |
| FastAPI | http://localhost:8000 | MobileNetV2 classifier (FastAPI) |
| Ray Serve | http://localhost:31800 | MobileNetV2 classifier (Ray Serve + FastAPI ingress) |
| Locust UI | http://localhost:8089 | Load testing web interface |

## API Endpoints

All services expose identical APIs for fair comparison:

### Predict Endpoint

```bash
# POST /predict
curl -X POST http://localhost:3000/predict \
  -H "Content-Type: application/json" \
  -d '{"image_base64": "<base64-encoded-image>"}'
```

Response:
```json
{
  "predictions": [
    {"class_id": 281, "class_name": "tabby cat", "confidence": 0.85}
  ],
  "top_prediction": "tabby cat",
  "confidence": 0.85
}
```

### Health Endpoint

```bash
# GET /health
curl http://localhost:3000/health
```

## Load Test Configuration (automated CLI)

- Script: `scripts/automated-loadtest.sh`
- Defaults: 10s per level; concurrencies `1 5 10 20`
- Uses generated base64 JPEG payloads; direct `curl` POSTs to `/predict`
- Outputs raw results to `tmp/loadtest_*.txt` and a Markdown summary to `tmp/loadtest_report.md`
- Override via env: `DURATION_PER_LEVEL=5 CONCURRENCY_LEVELS="1 5 10" ./scripts/automated-loadtest.sh`

Locust UI remains available at http://localhost:8089 if you prefer browser-driven tests (see locust_service/locustfile.py).

## Metrics Collected

| Metric | Description |
|--------|-------------|
| RPS | Requests per second |
| Response Time (p50/p95/p99) | Latency percentiles |
| Error Rate | Percentage of failed requests |
| Throughput | Total requests handled |

## Cleanup

Remove all resources:

```bash
./scripts/cleanup.sh
```

This removes:
- Kind cluster
- Docker images
- Virtual environment

## Troubleshooting

### Pods in CrashLoopBackOff

Check pod logs:
```bash
kubectl logs -n ml-benchmark -l app=bentoml-mobilenet
kubectl logs -n ml-benchmark -l app=fastapi-mobilenet
```

### Model Loading Errors

Ensure the model was saved with compatible TensorFlow/Keras versions:
```bash
# Rebuild model with pinned versions
uv pip install tensorflow==2.15.0
python model/download_model.py
```

### Port Already in Use

Check for existing processes:
```bash
lsof -i :3000
lsof -i :8000
lsof -i :8089
```

### Kind Cluster Issues

Delete and recreate:
```bash
kind delete cluster --name ml-benchmark
./scripts/deploy-k8s.sh
```

## License

MIT License
