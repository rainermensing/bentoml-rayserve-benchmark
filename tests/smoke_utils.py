import base64
import io
import os
from typing import Dict

import numpy as np
from PIL import Image


def generate_image_obj(width: int = 224, height: int = 224) -> Image.Image:
    """Create a small random JPEG and return PIL Image."""
    return Image.fromarray(
        np.random.randint(0, 255, (height, width, 3), dtype=np.uint8), "RGB"
    )

def generate_image_bytes(width: int = 224, height: int = 224) -> bytes:
    """Create a small random JPEG and return bytes."""
    img = generate_image_obj(width, height)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=80)
    return buf.getvalue()

def generate_image_b64(width: int = 224, height: int = 224) -> str:
    """Create a small random JPEG and return base64 string."""
    return base64.b64encode(generate_image_bytes(width, height)).decode()


def assert_prediction_body(body: Dict):
    preds = body.get("predictions")
    assert isinstance(preds, list) and len(preds) > 0, body
