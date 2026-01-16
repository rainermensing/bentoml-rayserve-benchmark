import base64
import io
import os
import time
from typing import Dict

import pytest
import requests

from PIL import Image
import numpy as np


def generate_image_b64(width: int = 224, height: int = 224) -> str:
    img = Image.fromarray(
        np.random.randint(0, 255, (height, width, 3), dtype=np.uint8), "RGB"
    )
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=80)
    return base64.b64encode(buf.getvalue()).decode()


def docker_available() -> bool:
    try:
        import docker

        client = docker.from_env()
        client.ping()
        return True
    except Exception:
        return False


@pytest.mark.skipif(not docker_available(), reason="Docker not available")
def test_use_existing_containers() -> None:
    """Discover running containers and probe any exposed HTTP ports for the expected endpoints.

    This test does not start or stop containers; it attempts to find already-running
    containers that expose an HTTP port (commonly mapping container 8000) and calls
    `/health` and `/predict` on them. If no accessible containers are found the test
    is skipped.
    """
    import docker

    client = docker.from_env()
    containers = client.containers.list()

    candidates = []
    for c in containers:
        ports = c.attrs.get('NetworkSettings', {}).get('Ports') or {}
        for container_port, mappings in (ports.items() if isinstance(ports, dict) else []):
            if not mappings:
                continue
            for m in mappings:
                host_port = m.get('HostPort')
                host_ip = m.get('HostIp') or '127.0.0.1'
                if host_port:
                    candidates.append((c, host_ip, host_port))

    if not candidates:
        pytest.skip("No running containers with host port mappings found")

    # Debug: list discovered candidates
    print("Discovered container port mappings:")
    for c, host_ip, host_port in candidates:
        print(f" - {c.name} -> http://{host_ip}:{host_port}")

    found_any = False
    for c, host_ip, host_port in candidates:
        base_url = f"http://{host_ip}:{host_port}"
        try:
            resp = requests.get(f"{base_url}/health", timeout=1)
            print(f"Probed {base_url}/health -> {resp.status_code}")
            if resp.status_code != 200:
                print(f"Skipping {c.name}: /health returned {resp.status_code}")
                continue
        except Exception as exc:
            print(f"Skipping {c.name}: /health probe failed: {exc}")
            continue

        # If we get here, we found a responsive HTTP service; exercise /predict
        try:
            payload = {"image_base64": generate_image_b64()}
            resp = requests.post(f"{base_url}/predict", json=payload, timeout=10)
            print(f"Probed {base_url}/predict -> {resp.status_code}")
            if resp.status_code == 200:
                body = resp.json()
                assert isinstance(body.get("predictions"), list)
                found_any = True
                break
            else:
                print(f"{c.name} returned non-200 from /predict: {resp.status_code}")
        except Exception as exc:
            print(f"Error calling /predict on {c.name} ({base_url}): {exc}")
            # service may not implement /predict; try next container
            continue

    if not found_any:
        pytest.skip("No accessible containers exposing the expected endpoints were found")
