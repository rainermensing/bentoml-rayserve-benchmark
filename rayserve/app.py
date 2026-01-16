"""
Ray Serve deployment for MobileNetV2 image classification.

The service uses Ray Serve + FastAPI ingress to expose the same API shape as the
existing BentoML and FastAPI demos: `/predict` and `/health`.
"""
from __future__ import annotations

import io
import os
import logging
import typing as t

import numpy as np
import tensorflow as tf
from fastapi import FastAPI, HTTPException, UploadFile, File, status
from pydantic import BaseModel
from PIL import Image
from ray import serve

# Configure logging
logger = logging.getLogger("ray.serve")

# Configuration constants with defaults
MODEL_PATH = os.getenv("MODEL_PATH", "/app/model/mobilenet_v2.keras")
LABELS_PATH = os.getenv("LABELS_PATH", "/app/imagenet_labels.txt")
NUM_REPLICAS = int(os.getenv("RAY_NUM_REPLICAS", "1"))
NUM_CPUS = float(os.getenv("RAY_NUM_CPUS", "2"))
MEMORY_BYTES = int(os.getenv("RAY_MEMORY_BYTES", str(2 * 1024 * 1024 * 1024)))

def load_labels(path: str) -> list[str]:
    """Load ImageNet labels from a file."""
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                return [line.strip() for line in f.readlines()]
        except Exception as e:
            logger.error(f"Failed to load labels from {path}: {e}")
    
    logger.warning("Using fallback labels (class_0, class_1, ...)")
    return [f"class_{i}" for i in range(1001)]

IMAGENET_LABELS = load_labels(LABELS_PATH)

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
    try:
        image = Image.open(io.BytesIO(image_data)).convert("RGB")
        image = image.resize((224, 224))
        image_array = np.array(image, dtype=np.float32) / 255.0
        return np.expand_dims(image_array, axis=0)
    except Exception as e:
        logger.error(f"Image preprocessing failed: {e}")
        raise ValueError(f"Invalid image data: {e}") from e


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
        logger.info(f"Loading model from {MODEL_PATH}")
        try:
            self.model = tf.keras.models.load_model(MODEL_PATH)
            logger.info("Model loaded successfully")
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            raise

    @fastapi_app.get("/health", response_model=HealthResponse)
    async def health(self) -> HealthResponse:
        return HealthResponse(status="healthy", service="rayserve-mobilenetv2")

    @serve.batch(max_batch_size=8, batch_wait_timeout_s=0.01)
    async def _batched_predict(self, requests: list[list[bytes]]) -> list[list[PredictResponse]]:
        """Batch incoming requests to share one model.predict call.
        
        Ray Serve's @serve.batch decorator aggregates concurrent calls to this method.
        'requests' is a list of what was passed to each call.
        """
        # Calculate how many images each request sent
        request_sizes = [len(req) for req in requests]
        # Flatten all images into a single list
        all_images = [img for req in requests for img in req]
        
        if not all_images:
             return [[] for _ in requests]

        try:
            # Preprocess all images
            tensors = [preprocess_image(img) for img in all_images]
            batch = np.vstack(tensors)
            
            # Perform inference on the whole batch
            predictions = self.model.predict(batch, verbose=0)
            
            # Post-process results
            all_results: list[PredictResponse] = []
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
                all_results.append(
                    PredictResponse(
                        predictions=results,
                        top_prediction=results[0].class_name,
                        confidence=results[0].confidence,
                    )
                )

            # Re-group results to match the original request structure
            responses: list[list[PredictResponse]] = []
            curr_idx = 0
            for size in request_sizes:
                responses.append(all_results[curr_idx : curr_idx + size])
                curr_idx += size
            return responses

        except Exception as exc:
            logger.exception("Error during batched prediction")
            # In a batch context, an exception here will be raised for all callers in the batch
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, 
                detail=f"Inference error: {str(exc)}"
            ) from exc

    @fastapi_app.post("/predict", response_model=list[PredictResponse])
    async def predict(self, files: list[UploadFile] = File(...)) -> list[PredictResponse]:
        """Endpoint for image classification. Accepts multiple files."""
        images_data = []
        for file in files:
            content = await file.read()
            images_data.append(content)
            
        if not images_data:
            raise HTTPException(status_code=400, detail="No images provided")

        # Call the batched predictor. Ray Serve will aggregate concurrent calls.
        return await self._batched_predict(images_data)

# Create the deployment graph
graph = MobileNetV2Deployment.bind()