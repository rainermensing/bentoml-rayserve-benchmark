import os

import pytest

tf = pytest.importorskip("tensorflow")

from tests.smoke_utils import assert_prediction_body, generate_image_b64


@pytest.mark.skipif(os.getenv("SKIP_RAY", "0") == "1", reason="Ray Serve skipped")
def test_rayserve_smoke_local():
    # Use the same preprocessing and labels as the Ray Serve app, but run locally without Serve.
    os.environ.setdefault("MODEL_PATH", "model/mobilenet_v2.keras")
    os.environ.setdefault("LABELS_PATH", "model/imagenet_labels.txt")

    import importlib
    app_mod = importlib.import_module("rayserve.app")

    model = tf.keras.models.load_model(os.getenv("MODEL_PATH"))

    img_b64 = generate_image_b64()
    import base64

    tensor = app_mod.preprocess_image(base64.b64decode(img_b64))
    preds = model.predict(tensor, verbose=0)

    # Reuse the Ray Serve response shaping logic
    top_indices = tf.argsort(preds[0])[-5:][::-1].numpy()
    results = []
    labels = app_mod.IMAGENET_LABELS
    for idx in top_indices:
        idx_int = int(idx)
        results.append(
            {
                "class_id": idx_int,
                "class_name": labels[idx_int] if idx_int < len(labels) else f"class_{idx_int}",
                "confidence": float(preds[0][idx_int]),
            }
        )

    body = {"predictions": results, "top_prediction": results[0]["class_name"], "confidence": results[0]["confidence"]}
    assert_prediction_body(body)
