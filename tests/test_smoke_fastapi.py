import os

import importlib.util
import pathlib

import pytest

fastapi = pytest.importorskip("fastapi")
tf = pytest.importorskip("tensorflow")
from fastapi.testclient import TestClient

from tests.smoke_utils import assert_prediction_body, generate_image_b64


@pytest.mark.skipif(os.getenv("SKIP_FASTAPI", "0") == "1", reason="FastAPI skipped")
def test_fastapi_smoke_local():
    # Ensure model files resolve locally
    os.environ.setdefault("MODEL_PATH", "model/mobilenet_v2.keras")
    os.environ.setdefault("LABELS_PATH", "model/imagenet_labels.txt")

    # Load the local fastapi/main.py module explicitly
    module_path = pathlib.Path(__file__).resolve().parents[1] / "fastapi" / "main.py"
    spec = importlib.util.spec_from_file_location("fastapi_app", module_path)
    assert spec and spec.loader, "Failed to load fastapi/main.py"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # type: ignore[arg-type]

    with TestClient(mod.app) as client:
        # Trigger startup and health
        resp = client.get("/health")
        assert resp.status_code == 200

        payload = {"image_base64": generate_image_b64()}
        resp = client.post("/predict", json=payload)
        assert resp.status_code == 200, resp.text
        assert_prediction_body(resp.json())
