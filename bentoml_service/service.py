"""
BentoML service for MobileNetV2 image classification.
"""

from __future__ import annotations

import typing as t
from pathlib import Path

import numpy as np
import bentoml
from bentoml.exceptions import InvalidArgument
from PIL import Image

# Get the directory where this service file is located
SERVICE_DIR = Path(__file__).parent

# Load ImageNet labels - look in same directory as service.py or in ../model/
LABELS_PATH = SERVICE_DIR / "imagenet_labels.txt"
if not LABELS_PATH.exists():
    LABELS_PATH = SERVICE_DIR.parent / "model" / "imagenet_labels.txt"

if LABELS_PATH.exists():
    with open(LABELS_PATH, "r") as f:
        IMAGENET_LABELS = [line.strip() for line in f.readlines()]
else:
    IMAGENET_LABELS = [f"class_{i}" for i in range(1001)]


runtime_image = bentoml.images.PythonImage(
    python_version="3.11"
).requirements_file(str(SERVICE_DIR / "requirements.txt"))


@bentoml.service(
    image=runtime_image,
    resources={"cpu": "1", "memory": "2Gi"},
    traffic={"timeout": 60},
)
class MobileNetV2Classifier:
    """BentoML service for MobileNetV2 image classification."""

    def __init__(self):
        import tensorflow as tf

        # Look for model in local dir or ../model/
        model_path = SERVICE_DIR / "mobilenet_v2.keras"
        if not model_path.exists():
            model_path = SERVICE_DIR.parent / "model" / "mobilenet_v2.keras"
            
        self.model = tf.keras.models.load_model(str(model_path))
        print(f"Model loaded from {model_path}")

    @bentoml.api(batchable=True)
    def predict(self, files: list[Image.Image]) -> list[dict[str, t.Any]]:
        """Predict image class from a batch of images.
        """
        # Preprocess batch
        # Resize and normalize
        processed_images = []
        for img in files:
            img = img.convert("RGB").resize((224, 224))
            img_array = np.array(img, dtype=np.float32) / 255.0
            processed_images.append(img_array)
        
        tensor = np.stack(processed_images)
        
        # Inference
        preds = self.model.predict(tensor, verbose=0)

        # Postprocess
        batch_results = []
        for pred in preds:
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
            
            batch_results.append({
                "predictions": results,
                "top_prediction": results[0]["class_name"],
                "confidence": results[0]["confidence"],
            })

        return batch_results

    @bentoml.api
    def health(self) -> dict[str, str]:
        """Health check endpoint."""
        return {"status": "healthy", "service": "bentoml-mobilenetv2"}
