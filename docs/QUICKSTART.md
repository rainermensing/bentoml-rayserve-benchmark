# BentoML vs FastAPI vs Ray Serve Benchmark - Quick Start Guide

## Prerequisites

1. **Docker** - For building container images
2. **Kubernetes Cluster** - minikube, kind, or cloud provider
3. **kubectl** - Configured for your cluster
4. **Python 3.9+** - For local testing

## Step 1: Set Up Kubernetes Cluster (if needed)

### Using Minikube
```bash
# Start minikube with enough resources
minikube start --cpus=4 --memory=8192 --driver=docker

# Enable metrics-server for HPA
minikube addons enable metrics-server
```

### Using Kind
```bash
# Create cluster
kind create cluster --name ml-benchmark

# Load local images (after building)
kind load docker-image ml-benchmark/bentoml-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/fastapi-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/rayserve-mobilenet:latest --name ml-benchmark
kind load docker-image ml-benchmark/locust-service:latest --name ml-benchmark
```

## Step 2: Download the Model

```bash
cd model
pip install -r requirements.txt
python download_model.py
cd ..
```

## Step 3: Build Docker Images

```bash
chmod +x scripts/*.sh
./scripts/build-images.sh
```

## Step 4: Deploy to Kubernetes

```bash
./scripts/deploy-k8s.sh
```

## Step 5: Set Up Port Forwarding

In separate terminals:

```bash
# Terminal 1 - BentoML
kubectl port-forward svc/bentoml-mobilenet 3000:3000 -n ml-benchmark

# Terminal 2 - FastAPI
kubectl port-forward svc/fastapi-mobilenet 8000:8000 -n ml-benchmark

# Terminal 3 - Ray Serve
kubectl port-forward svc/rayserve-mobilenet 31800:8000 -n ml-benchmark

# Terminal 4 - Locust UI (optional)
kubectl port-forward svc/locust-master 8089:8089 -n ml-benchmark
```

## Step 6: Run Load Tests

### Automated CLI Benchmark (Recommended)
This runs a sequence of load tests at increasing concurrency levels and generates a Markdown report.

```bash
./scripts/automated-loadtest.sh
```

### Manual Locust Testing
If you prefer to control the load test manually:
1. Open http://localhost:8089 in your browser.
2. Set the host to one of the following:
   - BentoML: `http://bentoml-mobilenet:3000`
   - FastAPI: `http://fastapi-mobilenet:8000`
   - Ray Serve: `http://rayserve-mobilenet:8000`
3. Start the test.

## Step 7: Analyze Results

If you ran the automated benchmark:
- **Report**: `tmp/loadtest_report.md`
- **Raw Data**: `tmp/loadtest_*.txt`

If you ran Locust manually, you can download the report from the web UI.

## Cleanup

```bash
./scripts/cleanup.sh
```

## Quick Test (Local)

Test services locally without Kubernetes:

```bash
# Terminal 1 - BentoML
cd bentoml
pip install -r requirements.txt
bentoml serve service:MobileNetV2Classifier --port 3000

# Terminal 2 - FastAPI
cd fastapi
pip install -r requirements.txt
uvicorn main:app --port 8000

# Terminal 3 - Ray Serve
cd rayserve
pip install -r requirements.txt
python app.py

# Terminal 4 - Run quick test
curl -X POST http://localhost:3000/predict \
  -H "Content-Type: application/json" \
  -d '{"image_base64": "/9j/4AAQ..."}'
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pods -n ml-benchmark
kubectl logs -f <pod-name> -n ml-benchmark
```

### Model not loading
- Ensure the model was downloaded successfully
- Check PVC is bound: `kubectl get pvc -n ml-benchmark`

### Port forwarding issues
- Make sure pods are in Running state
- Check service endpoints: `kubectl get endpoints -n ml-benchmark`
