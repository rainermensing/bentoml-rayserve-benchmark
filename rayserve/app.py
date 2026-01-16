"""
Ray Serve deployment for MobileNetV2 image classification.

The service uses Ray Serve + FastAPI ingress to expose the same API shape as the
existing BentoML and FastAPI demos: `/predict` and `/health`.
"""
from __future__ import annotations

import base64
import io
import os
import typing as t

import numpy as np
import tensorflow as tf
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from PIL import Image
from ray import serve

# Ray Serve HTTP binding (defaults to 0.0.0.0:8000 for container networking)
HTTP_PORT = int(os.getenv("SERVE_HTTP_PORT", os.getenv("PORT", "8000")))
os.environ.setdefault("SERVE_HTTP_HOST", "0.0.0.0")
os.environ.setdefault("SERVE_HTTP_PORT", str(HTTP_PORT))

MODEL_PATH = os.getenv("MODEL_PATH", "/app/model/mobilenet_v2.keras")
LABELS_PATH = os.getenv("LABELS_PATH", "/app/imagenet_labels.txt")
NUM_REPLICAS = int(os.getenv("RAY_NUM_REPLICAS", "1"))
NUM_CPUS = float(os.getenv("RAY_NUM_CPUS", "2"))
MEMORY_BYTES = int(os.getenv("RAY_MEMORY_BYTES", str(2 * 1024 * 1024 * 1024)))


def load_labels(path: str) -> list[str]:
    if os.path.exists(path):
        with open(path, "r") as f:
            return [line.strip() for line in f.readlines()]
    return [f"class_{i}" for i in range(1001)]


IMAGENET_LABELS = load_labels(LABELS_PATH)


class PredictRequest(BaseModel):
    image_base64: str


class PredictionResult(BaseModel):
    class_id: int
    class_name: str
    confidence: float


class PredictResponse(BaseModel):
    predictions: list[PredictionResult]
    top_prediction: str
    confidence: float


class HealthResponse(BaseModel):
    status: str
    service: str


def preprocess_image(image_data: bytes) -> np.ndarray:
    """Preprocess image for MobileNetV2."""
    image = Image.open(io.BytesIO(image_data)).convert("RGB")
    image = image.resize((224, 224))
    image_array = np.array(image, dtype=np.float32) / 255.0
    return np.expand_dims(image_array, axis=0)


fastapi_app = FastAPI(
    title="MobileNetV2 Classifier - Ray Serve",
    description="Ray Serve + FastAPI ingress for MobileNetV2",
    version="1.0.0",
)


@serve.deployment(
    num_replicas=NUM_REPLICAS,
    ray_actor_options={
        "num_cpus": NUM_CPUS,
        "memory": MEMORY_BYTES,
    },
)
@serve.ingress(fastapi_app)
class MobileNetV2Deployment:
    def __init__(self):
        # Disable TensorFlow logs to keep Ray worker logs clean
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
        self.model = tf.keras.models.load_model(MODEL_PATH)

    @fastapi_app.get("/health", response_model=HealthResponse)
    async def health(self) -> HealthResponse:
        return HealthResponse(status="healthy", service="rayserve-mobilenetv2")

    @serve.batch(max_batch_size=8, batch_wait_timeout_s=0.01)
    async def _batched_predict(self, requests: list[PredictRequest]) -> list[PredictResponse]:
        """Batch incoming requests to share one model.predict call."""
        try:
            tensors = [preprocess_image(base64.b64decode(req.image_base64)) for req in requests]
            batch = np.vstack(tensors)
            predictions = self.model.predict(batch, verbose=0)
        except Exception as exc:  # noqa: BLE001 - surfaced to caller
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        responses: list[PredictResponse] = []
        for pred in predictions:
            top_indices = np.argsort(pred)[-5:][::-1]
            results: list[PredictionResult] = []
            for idx in top_indices:
                class_name = IMAGENET_LABELS[idx] if idx < len(IMAGENET_LABELS) else f"class_{idx}"
                results.append(
                    PredictionResult(
                        class_id=int(idx),
                        class_name=class_name,
                        confidence=float(pred[idx]),
                    )
                )
            responses.append(
                PredictResponse(
                    predictions=results,
                    top_prediction=results[0].class_name,
                    confidence=results[0].confidence,
                )
            )

        return responses

    @fastapi_app.post("/predict", response_model=PredictResponse)
    async def predict(self, request: PredictRequest) -> PredictResponse:
        # Ray Serve will batch concurrent calls to _batched_predict; each caller receives one response.
        result = await self._batched_predict(request)
        return result[0] if isinstance(result, list) else result


graph = MobileNetV2Deployment.bind()
