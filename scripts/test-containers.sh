#!/usr/bin/env bash
set -euo pipefail

# Test containerized services (assumes images already built locally)
# Usage: ./scripts/test-containers.sh [image1 image2 ...]

WD=$(cd "$(dirname "$0")/.." && pwd)
cd "$WD"

IMAGES=("ml-benchmark/fastapi-mobilenet:latest" "ml-benchmark/bentoml-mobilenet:latest" "ml-benchmark/rayserve-mobilenet:latest")
if [ $# -gt 0 ]; then
  IMAGES=("$@")
fi

start_and_test() {
  local image="$1"
  local name
  name=$(echo "$image" | sed 's/[^a-zA-Z0-9]/_/g')
  cname="test_${name}_$$"

  echo "\n=== Testing image: $image (container: $cname) ==="

  cid=$(docker run -d --rm -P --name "$cname" "$image" 2>&1 | tail -n1 || true)
  if [ -z "$cid" ]; then
    echo "Failed to start container for $image" >&2
    return 1
  fi

  # get mapped port heuristically: prefer 8000 then 3000
  mapped_port=""
  for port in 8000 3000; do
    mapped=$(docker port "$cid" ${port}/tcp 2>/dev/null || true)
    if [ -n "$mapped" ]; then
      mapped_port=$(echo "$mapped" | sed 's/.*://;q')
      break
    fi
  done

  if [ -z "$mapped_port" ]; then
    echo "Could not determine mapped port for $image (cid=$cid)" >&2
    docker logs "$cid" --tail 100 || true
    docker rm -f "$cid" || true
    return 1
  fi

  echo "Mapped port: $mapped_port"

  # wait for /health
  for i in $(seq 1 60); do
    # ensure container is still running
    running=$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)
    if [ "$running" != "true" ]; then
      echo "Container $cid exited unexpectedly" >&2
      docker logs "$cid" --tail 200 || true
      docker rm -f "$cid" >/dev/null 2>&1 || true
      return 1
    fi
    if curl -sS -f http://localhost:$mapped_port/health >/dev/null 2>&1; then
      echo "/health OK"
      break
    fi
    sleep 0.5
  done

  # POST using Python (avoids shell quoting/padding issues with very long base64 strings)
  echo "Posting to /predict via Python client..."
  export MAPPED_PORT=$mapped_port

  # Helper to call predict with a given image size. Python prints a STATUS:<code> line then the body.
  call_predict() {
    local size=$1
    python3 - <<PY
import os, base64, io, requests, sys, json
from PIL import Image
import numpy as np
port = os.environ.get('MAPPED_PORT')
if not port:
    print('STATUS:ERR')
    sys.exit(2)
img = Image.fromarray((np.random.rand($size,$size,3)*255).astype('uint8'))
buf = io.BytesIO(); img.save(buf, 'JPEG')
img_b64 = base64.b64encode(buf.getvalue()).decode()
try:
    r = requests.post(f'http://localhost:{port}/predict', json={'image_base64': img_b64}, timeout=60)
    print(f'STATUS:{r.status_code}')
    try:
        print(json.dumps(r.json()))
    except Exception:
        print(r.text[:1000])
except Exception as e:
    print('STATUS:ERR')
    print(str(e))
    sys.exit(1)
PY
  }

  # Try full-size then smaller sizes if Bento complains about base64 padding.
  out=$(call_predict 224)
  status=$(echo "$out" | sed -n '1p' | sed 's/^STATUS://') || true
  echo "$out" | sed -n '2,200p'
  if [ "$status" = "400" ] || [ "$status" = "ERR" ]; then
    # Check if response contains the Invalid base64 marker; if so, retry smaller images
    body=$(echo "$out" | sed -n '2,200p')
    if echo "$body" | grep -qi "Invalid base64" || [ "$status" = "ERR" ]; then
      echo "Predict failed with base64 error, retrying smaller images..."
      for s in 128 64; do
        echo "Trying size $s"
        out=$(call_predict $s)
        status=$(echo "$out" | sed -n '1p' | sed 's/^STATUS://') || true
        echo "$out" | sed -n '2,200p'
        if [ "$status" = "200" ]; then
          break
        fi
      done
    fi
  fi


  echo "---- Container logs (tail 200) ----"
  docker logs "$cid" --tail 200 || true

  docker rm -f "$cid" >/dev/null 2>&1 || true
  echo "Done testing $image"
}

for img in "${IMAGES[@]}"; do
  start_and_test "$img"
done

echo "\nAll done."
