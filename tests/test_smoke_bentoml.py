import os

import pathlib
import importlib.util

import pytest

bentoml = pytest.importorskip("bentoml")
tf = pytest.importorskip("tensorflow")

from tests.smoke_utils import assert_prediction_body, generate_image_obj


@pytest.mark.skipif(os.getenv("SKIP_BENTOML", "0") == "1", reason="BentoML skipped")
def test_bentoml_smoke_local():
    # Model bundled next to service.py; no env override needed
    module_path = pathlib.Path(__file__).resolve().parents[1] / "bentoml_service" / "service.py"
    spec = importlib.util.spec_from_file_location("bentoml_service", module_path)
    assert spec and spec.loader, "Failed to load bentoml_service/service.py"
    svc_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(svc_mod)  # type: ignore[arg-type]
    svc = svc_mod.MobileNetV2Classifier()

    image = generate_image_obj()
    # Predict expects a list of images (batch)
    results = svc.predict([image])

    assert isinstance(results, list)
    assert len(results) == 1
    assert_prediction_body(results[0])
