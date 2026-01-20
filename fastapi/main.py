"""Minimal FastAPI app used by smoke tests.

Exposes `/health` and `/predict` endpoints. Loads a Keras model from
`MODEL_PATH` and labels from `LABELS_PATH` environment variables.
"""

from __future__ import annotations

import io
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Union
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, HTTPException, UploadFile, File
from PIL import Image

# Prefer environment variables set by tests or Dockerfile
MODEL_PATH = os.getenv("MODEL_PATH", "model/mobilenet_v2.keras")
LABELS_PATH = os.getenv("LABELS_PATH", "imagenet_labels.txt")

# Load labels
labels_file = Path(LABELS_PATH)
if labels_file.exists():
    with open(labels_file, "r") as f:
        IMAGENET_LABELS = [line.strip() for line in f.readlines()]
else:
    IMAGENET_LABELS = [f"class_{i}" for i in range(1001)]


def preprocess_image(image_data: bytes) -> np.ndarray:
    image = Image.open(io.BytesIO(image_data)).convert("RGB")
    image = image.resize((224, 224))
    image_array = np.array(image, dtype=np.float32) / 255.0
    return np.expand_dims(image_array, axis=0)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context: load model on startup and clear on shutdown."""
    # Load model into app.state so it's accessible in request handlers
    try:
        import tensorflow as tf

        model_path = Path(MODEL_PATH)
        app.state.model = tf.keras.models.load_model(str(model_path))
        app.state._model_load_exception = None
    except Exception as exc:  # pragma: no cover - environment dependent
        app.state.model = None
        app.state._model_load_exception = exc
    try:
        yield
    finally:
        if hasattr(app.state, "model"):
            app.state.model = None


app = FastAPI(lifespan=lifespan)


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "healthy", "service": "fastapi-mobilenetv2"}


@app.post("/predict")
async def predict(file: UploadFile = File(...)) -> Any:
    model = getattr(app.state, "model", None)
    if model is None:
        raise HTTPException(status_code=500, detail=f"Model not loaded: {getattr(app.state, '_model_load_exception', None)}")

    content = await file.read()
    input_tensor = preprocess_image(content)
    
    # Simple single prediction
    preds = model.predict(input_tensor, verbose=0)
    pred = preds[0]

    top_indices = np.argsort(pred)[-5:][::-1]
    results = []
    for idx in top_indices:
        results.append(
            {
                "class_id": int(idx),
                "class_name": IMAGENET_LABELS[idx] if idx < len(IMAGENET_LABELS) else f"class_{idx}",
                "confidence": float(pred[idx]),
            }
        )
    
    # Return as a list with one item to match the response shape of the other services
    return [{
        "predictions": results,
        "top_prediction": results[0]["class_name"],
        "confidence": results[0]["confidence"],
    }]