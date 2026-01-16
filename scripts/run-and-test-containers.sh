#!/usr/bin/env bash
set -euox pipefail

# Start containers from built images, publish ports randomly, probe /health and /predict, then clean up.
# Usage: ./scripts/run-and-test-containers.sh

WD=$(cd "$(dirname "$0")/.." && pwd)
cd "$WD"

CONTAINERS=()
cleanup() {
  echo "Cleaning up containers..."
  for c in "${CONTAINERS[@]:-}"; do
    docker rm -f "$c" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

start_container() {
  local name=$1 image=$2
    echo "Starting $name from image $image"
    # Run detached, capture the container id. If docker prints errors before the id,
    # we still want only the id returned from this function.
    id=$(docker run -d --rm -P --name "$name" "$image" 2>&1 | tail -n1 || true)
    # Validate we have a reasonable id (64+ hex chars) and that container exists
    if [ -n "$id" ] && docker ps -a --no-trunc --filter "id=$id" --format '{{.ID}}' | grep -q .; then
        echo "$id"
    else
        echo ""
    fi
}

FASTAPI_CID=$(start_container mobilenet_fastapi_test ml-benchmark/fastapi-mobilenet:latest)
if [ -n "$FASTAPI_CID" ]; then
    CONTAINERS+=("$FASTAPI_CID")
else
    echo "Failed to start FastAPI container from ml-benchmark/fastapi-mobilenet:latest" >&2
fi

BENTO_CID=$(start_container mobilenet_bentoml_test ml-benchmark/bentoml-mobilenet:latest)
if [ -n "$BENTO_CID" ]; then
    CONTAINERS+=("$BENTO_CID")
else
    echo "Failed to start BentoML container from ml-benchmark/bentoml-mobilenet:latest" >&2
fi

RAY_CID=$(start_container mobilenet_rayserve_test ml-benchmark/rayserve-mobilenet:latest)
if [ -n "$RAY_CID" ]; then
    CONTAINERS+=("$RAY_CID")
else
    echo "Failed to start RayServe container from ml-benchmark/rayserve-mobilenet:latest" >&2
fi

echo "Waiting a few seconds for services to start..."
sleep 2

docker_port() {
    local cid=$1 cport=$2
    if [ -z "$cid" ]; then
        echo ""
        return
    fi
    # docker port returns HOST:PORT, we strip host
    docker port "$cid" "$cport" 2>/dev/null | sed 's/.*://;q' || true
}

FASTAPI_PORT=$(docker_port $FASTAPI_CID 8000/tcp || true)
BENTO_PORT=$(docker_port $BENTO_CID 3000/tcp || true)
RAY_PORT=$(docker_port $RAY_CID 8000/tcp || true)

echo "FastAPI -> http://localhost:${FASTAPI_PORT:-<unknown>}"
echo "BentoML -> http://localhost:${BENTO_PORT:-<unknown>}"
echo "RayServe -> http://localhost:${RAY_PORT:-<unknown>}"

python3 - <<'PY'
import base64, io, time, requests, sys
from PIL import Image
import numpy as np

def gen_b64():
    img = Image.fromarray(np.random.randint(0,255,(224,224,3),dtype='uint8'))
    buf = io.BytesIO(); img.save(buf, format='JPEG'); return base64.b64encode(buf.getvalue()).decode()

hosts = [
    ('fastapi', 'http://localhost:%s' % ('$FASTAPI_PORT')),
    ('bentoml', 'http://localhost:%s' % ('$BENTO_PORT')),
    ('rayserve', 'http://localhost:%s' % ('$RAY_PORT')),
]

for name, base in hosts:
    if '<unknown>' in base or base.endswith(':'):
        print('Skipping', name, 'no mapped port')
        continue
    ok = False
    for _ in range(60):
        try:
            r = requests.get(base + '/health', timeout=1)
            print(name, '/health', r.status_code, r.text[:200])
            if r.status_code == 200:
                ok = True; break
        except Exception:
            time.sleep(0.5)
    if not ok:
        print('No healthy', name, 'at', base)
        continue
    payload = { 'image_base64': gen_b64() }
    try:
        r = requests.post(base + '/predict', json=payload, timeout=20)
        print(name, '/predict', r.status_code)
        if r.status_code == 200:
            print('Response keys:', list(r.json().keys()))
            print('Sample output (truncated):', str(r.json())[:500])
        else:
            print('Predict error body:', r.text[:500])
    except Exception as e:
        print('Error calling predict for', name, e)
PY

echo "Done. Containers will be removed on exit."
