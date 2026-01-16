"""
BentoML service for MobileNetV2 image classification.
"""

from __future__ import annotations

import typing as t
import base64
import io
from pathlib import Path

import numpy as np
import bentoml
from bentoml.exceptions import InvalidArgument
from bentoml.io import JSON
from PIL import Image

# Get the directory where this service file is located
SERVICE_DIR = Path(__file__).parent

# Load ImageNet labels - look in same directory as service.py
LABELS_PATH = SERVICE_DIR / "imagenet_labels.txt"

if LABELS_PATH.exists():
    with open(LABELS_PATH, "r") as f:
        IMAGENET_LABELS = [line.strip() for line in f.readlines()]
else:
    IMAGENET_LABELS = [f"class_{i}" for i in range(1001)]


def preprocess_image(image_data: bytes) -> np.ndarray:
    """Preprocess image for MobileNetV2."""
    image = Image.open(io.BytesIO(image_data)).convert("RGB")
    image = image.resize((224, 224))
    image_array = np.array(image, dtype=np.float32) / 255.0
    return np.expand_dims(image_array, axis=0)


@bentoml.service(
    resources={"cpu": "2", "memory": "2Gi"},
    traffic={"timeout": 60},
)
class MobileNetV2Classifier:
    """BentoML service for MobileNetV2 image classification."""

    def __init__(self):
        import tensorflow as tf

        # Model is in the same directory as the service (bundled with source)
        model_path = SERVICE_DIR / "mobilenet_v2.keras"
        self.model = tf.keras.models.load_model(str(model_path))
        print(f"Model loaded from {model_path}")

    # BentoML 1.4 SDK expects pydantic models/dict for IO conversion
    @bentoml.api(input_spec=dict, output_spec=dict)
    def predict(self, payload: dict[str, t.Any]) -> dict[str, t.Any]:
        """Predict image class from base64-encoded image (single request).

        This matches the previous working behavior before the batchable change.
        """

        if not isinstance(payload, dict):
            raise InvalidArgument("Request body must be a JSON object")

        img_b64 = payload.get("image_base64")
        if not isinstance(img_b64, str) or not img_b64:
            raise InvalidArgument("Field 'image_base64' must be a non-empty base64 string")

        # Be tolerant of whitespace/newlines and missing padding
        s = img_b64.strip().replace('\n', '').replace('\r', '')
        # add padding if needed
        missing = len(s) % 4
        if missing:
            s += '=' * (4 - missing)

        try:
            decoded = base64.b64decode(s)
        except Exception as exc:
            raise InvalidArgument("Invalid base64 for 'image_base64'") from exc

        tensor = preprocess_image(decoded)
        preds = self.model.predict(tensor, verbose=0)

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

        return {
            "predictions": results,
            "top_prediction": results[0]["class_name"],
            "confidence": results[0]["confidence"],
        }

    @bentoml.api
    def health(self) -> dict[str, str]:
        """Health check endpoint."""
        return {"status": "healthy", "service": "bentoml-mobilenetv2"}
