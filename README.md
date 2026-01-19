# BentoML vs FastAPI vs Ray Serve Benchmark

A comprehensive load testing comparison between BentoML, FastAPI, and Ray Serve for serving TensorFlow models in Kubernetes using Kind.

## Overview

This benchmark compares the performance of three popular ML model serving frameworks:
- **BentoML**: A unified model serving framework with native Kubernetes support (pinned 1.4.33)
- **FastAPI**: A high-performance Python web framework with uvicorn
- **Ray Serve**: A distributed model serving framework built on Ray (pinned 2.53.0)

Both services use **MobileNetV2** (pre-trained on ImageNet) for image classification.

## Setup & Usage

For detailed installation, deployment, and troubleshooting instructions, please refer to [SETUP.md](SETUP.md).

**Quick Start:**
```bash
make setup     # Prepare environment and deploy
make locust    # Run Locust load test
```

## Project Structure

```
.
├── README.md                    # This file
├── SETUP.md                     # Setup, usage, and troubleshooting guide
├── Makefile                     # Shortcut targets
├── kind-config.yaml             # Kind cluster configuration
├── model/                       # Model download scripts
├── bentoml/                     # BentoML service definition
├── fastapi/                     # FastAPI service definition
├── rayserve/                    # Ray Serve service definition
├── kubernetes/                  # K8s manifests
├── locust_service/              # Locust load testing scripts
├── scripts/                     # Helper scripts (build, deploy, test)
└── reports/                     # Generated benchmark reports & charts
```

## Benchmark Results

The following results were generated using **Locust** on a local Kind cluster (see [reports/locust/locust_comparison.md](reports/locust/locust_comparison.md) for the full report).

### 🏆 Executive Summary
**Winner:** **BentoML** demonstrated the highest throughput and lowest latency in this specific configuration.

### 📊 Visual Comparison

#### Throughput (Requests per Second)
![Throughput Comparison](reports/locust/locust_throughput.png)

#### Latency (Response Time)
![Latency Comparison](reports/locust/locust_latency.png)

### 📈 Aggregated Metrics

| Metric | BentoML | FastAPI | Ray Serve | Winner |
| :--- | :--- | :--- | :--- | :--- |
| **Throughput (req/s)** | **44.50** | 23.26 | 34.93 | **BentoML** |
| **Avg Latency (ms)** | **891.35** | 1942.87 | 1199.53 | **BentoML** |
| **P50 Latency (ms)** | **1000.00** | 2000.00 | 1400.00 | **BentoML** |
| **P95 Latency (ms)** | **1500.00** | 3100.00 | 1900.00 | **BentoML** |
| **Total Requests** | **2628** | 1359 | 2063 | **BentoML** |

*Note: Results may vary based on hardware and background processes.*

## ⚠️ Limitations of Local Benchmark

It is important to interpret these results within the context of a local development environment. This benchmark is intended for **relative comparison** and **functional validation**, not as an absolute measure of production performance.

1.  **Resource Contention (Shared Host):**
    *   **Client-Server Contention:** Although tests run **sequentially**, the load generator (Locust) and the active service (in Kind) run on the *same physical machine*. The CPU cycles used to generate load directly compete with the CPU cycles needed to serve requests.
    *   **Idle Overhead:** Even when testing one service, the other two services remain running in the background (idle), consuming memory and causing context switching overhead.

2.  **Network Loopback:**
    *   Traffic does not traverse a real network interface. Latency numbers exclude real-world RTT (Round Trip Time), packet loss, and jitter found in production networks.
    *   Docker internal networking (bridge mode) introduces its own specific overhead that differs from CNI plugins used in cloud providers (like AWS VPC CNI or Calico).

3.  **Single-Node "Cluster":**
    *   Kind runs as a single Docker container mimicking a K8s node.
    *   **Ray Serve** and **Kubernetes** are designed for distributed systems. Their primary advantage—horizontal scaling across multiple physical nodes—cannot be tested here. We are effectively benchmarking the overhead of their management planes on a single node rather than their scaling capabilities.

4.  **Resource Limits:**
    *   Docker Desktop creates a VM (on macOS) with hard limits. If the VM is allocated only 4GB or 8GB of RAM, swapping can occur, severely degrading performance for memory-heavy ML workloads.

## License

MIT License