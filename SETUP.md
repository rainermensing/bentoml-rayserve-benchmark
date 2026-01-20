# Setup & Usage Guide

## Prerequisites

- **Docker Desktop** (with at least 8GB RAM allocated)
- **Kind** (Kubernetes in Docker): `brew install kind`
- **kubectl**: `brew install kubectl`
- **uv** (fast Python package manager): `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **Python 3.11**

## Quick Start

The benchmark uses **Sequential Cluster Mode**, where each service is tested in its own isolated Kind cluster.

### Option 1: One-liners (Makefile)

```bash
make setup            # Prepare environment and download model
make build            # Build images and run smoke tests
make locust           # Run Locust load test (sequential clusters)
make loadtest         # Run generic concurrency sweep (sequential clusters)
make process-locust   # Generate consolidated Locust reports
make cleanup          # Tear everything down
```

### Option 2: Scripted (fine-grained)

```bash
# 1) Prepare
make setup

# 2) Build
./scripts/build-images.sh

# 3) Run tests (Duration 50s, 100 users)
./scripts/locust/run-locust-tests.sh 50s 100 3 2
```

## Accessing Services

During a test run, the active service is port-forwarded to:

| Service | Local URL | Port |
|---------|-----------|------|
| BentoML | http://localhost:3000 | 3000 |
| FastAPI | http://localhost:8000 | 8000 |
| Ray Serve | http://localhost:31800 | 31800 |

## API Endpoints

All services expose identical APIs for fair comparison:

### Predict Endpoint (Multipart Form Data)

The benchmark uses image uploads for `/predict`.

```bash
# Example manual request
curl -X POST http://localhost:3000/predict \
  -F "files=@/path/to/image.jpg"
```

## Troubleshooting

### Resource Exhaustion
If tests fail with timeouts or connection errors, ensure Docker Desktop has enough memory and CPU (8GB RAM / 4 CPUs recommended). Sequential cluster mode helps isolate services, but the load generator and Kind still share host resources.

### Cluster Cleanup
If a test is interrupted, clusters might remain. Use `make cleanup` to remove all benchmark-related Kind clusters:
- `ml-benchmark-bentoml`
- `ml-benchmark-fastapi`
- `ml-benchmark-rayserve`

### Pods not starting
Check pod logs in the active cluster:
```bash
kubectl logs -f deployment/bentoml-mobilenet -n ml-benchmark
```

### Model loading
Ensure `model/mobilenet_v2.keras` exists. If not, run `make setup`.

