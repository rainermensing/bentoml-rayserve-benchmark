# Service Implementation Details

This document provides a detailed overview of the implementation of the three microservices benchmarked in this project: BentoML, FastAPI, and Ray Serve. All services deploy the same MobileNetV2 image classification model to ensure a fair comparison.

## Shared Components

All services share the following core logic and resources:

*   **Model:** MobileNetV2 (TensorFlow/Keras application), pre-trained on ImageNet.
*   **Input Processing:**
    *   Images are resized to `224x224` pixels.
    *   Pixel values are normalized to the `[0, 1]` range (divided by 255.0).
    *   Input is converted to a batch tensor (even for single images).
*   **Output Format:** JSON response containing the top 5 predictions, each with:
    *   `class_id`: Integer ID of the class.
    *   `class_name`: Human-readable label (from `imagenet_labels.txt`).
    *   `confidence`: Probability score (float).
*   **Dependencies:** `tensorflow`, `pillow`, `numpy`.

---

## 1. BentoML Service

**Location:** `bentoml_service/service.py`

BentoML is a framework designed specifically for serving machine learning models. It abstracts away much of the boilerplate associated with API server setup and provides built-in support for adaptive batching.

### Key Implementation Details

*   **Framework:** `bentoml` (wrapping the class-based service).
*   **Service Definition:**
    *   The service is defined using the `@bentoml.service` decorator on the `MobileNetV2Classifier` class.
    *   Resources are explicitly defined: `resources={"cpu": "1", "memory": "2Gi"}`.
    *   Traffic configuration sets a timeout: `traffic={"timeout": 60}`.
*   **Model Loading:**
    *   The model is loaded in the `__init__` method using `tf.keras.models.load_model`.
    *   It looks for the model file in the local directory or a shared `../model/` directory.
*   **Request Handling (`predict` endpoint):**
    *   Decorated with `@bentoml.api`.
    *   **Adaptive Batching:** Enabled via parameters `batchable=True` and `max_batch_size=8`.
    *   **Input Type:** Accepts `files: list[Image.Image]`. BentoML automatically handles image decoding before passing data to the function.
    *   **Logic:**
        1.  Iterates through the batch of images.
        2.  Preprocesses each image (resize, normalize).
        3.  Stacks them into a single NumPy array (`np.stack`).
        4.  Runs inference (`self.model.predict`).
        5.  Formats the output for each request in the batch.
*   **Health Check:** A standard `health` endpoint returns a simple status dictionary.

---

## 2. FastAPI Service

**Location:** `fastapi/main.py`

FastAPI is a general-purpose, high-performance web framework for building APIs with Python. This implementation represents a "do-it-yourself" approach where the developer manages the server lifecycle and request processing manually.

### Key Implementation Details

*   **Framework:** `fastapi` + `uvicorn` (server).
*   **Model Loading:**
    *   Uses a `lifespan` async context manager.
    *   The model is loaded into `app.state.model` when the application starts and cleared on shutdown.
    *   This ensures the model is loaded only once and shared across requests.
*   **Request Handling (`/predict` endpoint):**
    *   Defined as an async route: `@app.post("/predict")`.
    *   **Input:** Accepts a single file upload via `UploadFile`.
    *   **Batching:** **Not implemented.** Requests are processed individually as they arrive.
    *   **Logic:**
        1.  Reads bytes from the uploaded file.
        2.  Decodes and preprocesses the image using `PIL` and `numpy`.
        3.  Runs inference on a single-item batch (`np.expand_dims`).
        4.  Returns the top 5 predictions.
*   **Health Check:** A `/health` endpoint is available for readiness probes.

---

## 3. Ray Serve Service

**Location:** `rayserve/app.py`

Ray Serve is a scalable model serving library built on Ray. It excels at composing complex inference pipelines and scaling across a cluster. This implementation uses Ray Serve's integration with FastAPI for ingress.

### Key Implementation Details

*   **Framework:** `ray.serve` interacting with a `FastAPI` app for ingress.
*   **Deployment Configuration:**
    *   Decorated with `@serve.deployment`.
    *   Specifies `num_replicas=1` (configurable via env vars), `num_cpus`, and `memory`.
    *   Decorated with `@serve.ingress(fastapi_app)` to route HTTP requests to the class methods.
*   **Model Loading:**
    *   Loaded in `__init__` using `tf.keras.models.load_model`.
    *   Includes logic to suppress TensorFlow logs for cleaner Ray worker output.
*   **Request Handling (`/predict` endpoint):**
    *   The external API is defined using standard FastAPI decorators (e.g., `@fastapi_app.post("/predict")`).
    *   Accepts a list of files: `files: list[UploadFile]`.
    *   **Batched Inference:**
        *   The actual inference logic resides in a separate internal method `_batched_predict`.
        *   Decorated with `@serve.batch(max_batch_size=8, batch_wait_timeout_s=0.01)`.
        *   **Mechanism:** Ray Serve automatically aggregates concurrent calls to `_batched_predict` from multiple requests into a single list argument.
        *   **Logic:**
            1.  Flattens the list of lists of images (from potentially multiple user requests).
            2.  Preprocesses all images into a single large batch.
            3.  Runs inference once (`self.model.predict`).
            4.  Splits the results back out to match the original requests.
*   **Health Check:** A `/health` endpoint is exposed via the FastAPI ingress.

---

## Service Processing Comparison

This section details the differences in request handling and image processing implementation between the three services. While all services achieve the same goal (MobileNetV2 classification), their implementation details vary significantly.

### 1. Input Handling & Request Structure

The most distinct difference lies in how files are received and how the API signature is defined.

| Feature | BentoML | FastAPI | Ray Serve |
| :--- | :--- | :--- | :--- |
| **API Argument** | `files` | `file` | `files` |
| **Type Annotation** | `list[Image.Image]` | `UploadFile` | `list[UploadFile]` |
| **Multi-file Support**| **Yes** (Native) | **No** (Single file only) | **Yes** (Manual loop) |
| **Decoding** | **Implicit** (Framework) | **Explicit** (Manual `PIL.Image.open`) | **Explicit** (Manual `PIL.Image.open`) |

*   **BentoML** abstracts raw bytes entirely. The handler receives ready-to-use `PIL.Image` objects.
*   **FastAPI** requires manual handling of the file stream (`await file.read()`) and manual decoding. It is strictly limited to one file per request in the current implementation.
*   **Ray Serve** also requires manual byte reading and decoding but loops over a list of uploaded files, supporting multiple images per request.

**Note:** The load testing script (`scripts/locust/locustfile.py`) explicitly adapts to these differences by changing the form field name from `file` (FastAPI) to `files` (others) based on the target port.

### 2. Image Preprocessing Logic

All services implement the same mathematical transformation:
1.  Convert to RGB.
2.  Resize to `224x224`.
3.  Normalize to `float32` in `[0, 1]`.

However, the tensor construction differs slightly:

#### BentoML
*   **Approach:** Iterates input list, creates `(224, 224, 3)` arrays, appends to list.
*   **Batching:** Uses `np.stack(list)` to create `(N, 224, 224, 3)`.

#### Ray Serve
*   **Approach:** Helper function `preprocess_image` returns `(1, 224, 224, 3)` (using `np.expand_dims`).
*   **Batching:** Uses `np.vstack(list)` to create `(N, 224, 224, 3)`.
*   **Reason:** This helper is used to ensure consistency with standard Keras input shapes and allows for potential reuse in single-item contexts.

#### FastAPI
*   **Approach:** Same helper as Ray Serve (`preprocess_image`), returning `(1, 224, 224, 3)`.
*   **Batching:** No real batching. The single array is passed directly to `model.predict`.

### 3. Batching Implementation

| Service | Strategy | Details |
| :--- | :--- | :--- |
| **BentoML** | **Adaptive Batching** | Built-in to the framework (`batchable=True`). It aggregates requests *across* different HTTP connections into a single model call automatically. |
| **Ray Serve** | **Adaptive Batching** | Explicitly defined via `@serve.batch`. Similar to BentoML, it aggregates concurrent calls to `_batched_predict`. |
| **FastAPI** | **None** | Processes requests 1-to-1. Under high load, this will likely lead to lower throughput compared to the other two as it cannot exploit vectorization for concurrent requests. |

### 4. Error Handling

*   **BentoML:** relies mostly on framework-level error handling. Invalid image data might raise exceptions during framework decoding before reaching user code.
*   **Ray Serve:** has explicit `try/except` blocks in `preprocess_image` and `_batched_predict` to catch invalid data and return `400 Bad Request`.
*   **FastAPI:** raises `HTTPException(500)` if the model is not loaded, but assumes image data is valid (no explicit try/catch around `Image.open`).

### Conclusion

*   **BentoML** offers the cleanest implementation code by offloading decoding and batching to the framework.
*   **Ray Serve** requires more boilerplate (manual decoding, explicit batching decorators) but offers granular control.
*   **FastAPI** is the simplest "bare metal" implementation but lacks the critical adaptive batching feature for high-throughput serving, making it a baseline rather than an optimized competitor in this specific configuration.

---

## Batching Optimization & Configuration

The two batching-enabled services use fundamentally different configuration paradigms, which significantly impact performance characteristics under varying loads:

### Ray Serve: Explicit Timeout (`batch_wait_timeout_s`)
Ray Serve uses a deterministic "wait and see" approach.
*   **Parameter:** `batch_wait_timeout_s=0.01` (10ms)
*   **Mechanism:** When a request arrives, the server waits *strictly* up to 10ms for additional requests to fill the batch (up to `max_batch_size`). If the batch fills sooner, it executes immediately.
*   **Optimization:** This value is a manual trade-off.
    *   **Too Low:** High overhead as batches are processed partially filled (low throughput).
    *   **Too High:** Increased latency for every request, even if the batch never fills.
*   **Helper:** We also use a `batch_size_fn` to ensure the `max_batch_size` limit applies to the total number of images (tensor size) rather than just the number of HTTP requests.

### BentoML: SLO-based Adaptive Batching (`max_latency_ms`)
BentoML uses an "Adaptive Batching" algorithm driven by a Service Level Objective (SLO).
*   **Parameter:** `max_latency_ms=60000` (60 seconds)
*   **Mechanism:** This high value effectively unconstrains the adaptive batching scheduler's latency budget.
*   **Optimization Strategy (Greedy Execution):** 
    *   For lightweight models like MobileNetV2, the compute time is often shorter than the time spent waiting for a batch to fill. 
    *   By setting a very loose SLO, we allow BentoML to behave "greedily"—it processes whatever requests are currently available in the queue without forcing an artificial wait period. 
    *   Benchmark data shows this yields the **best overall balance of latency and throughput** for this specific model, as it avoids the "idle wait" penalty while still allowing for natural batching during high-concurrency bursts.
