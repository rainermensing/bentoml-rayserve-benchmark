#!/usr/bin/env bash
set -euo pipefail

# Start containers from built images one by one, probe /health and /predict, then clean up.
# Usage: ./scripts/run-and-test-containers.sh

WD=$(cd "$(dirname "$0")/.." && pwd)
cd "$WD"

start_container() {
    local name=$1 image=$2
    echo "Starting $name from image $image" >&2
    # Run detached, capture the container id.
    id=$(docker run -d -P --name "$name" "$image" 2>&1 | tail -n1 || true)
    # Validate we have a reasonable id (64+ hex chars) and that container exists
    if [ -n "$id" ] && docker ps -a --no-trunc --filter "id=$id" --format '{{.ID}}' | grep -q .; then
        echo "$id"
    else
        echo ""
    fi
}

docker_port() {
    local cid=$1 cport=$2
    if [ -z "$cid" ]; then
        echo ""
        return
    fi
    # docker port returns HOST:PORT, we strip host
    docker port "$cid" "$cport" 2>/dev/null | sed 's/.*://;q' || true
}

run_test() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local file_key=$4

    echo "================================================"
    echo "Testing $service_name..."
    CID=$(start_container "${service_name}_test" "$image")
    if [ -z "$CID" ]; then echo "Failed to start $service_name"; return; fi
    
    # Wait a bit for startup
    sleep 5
    
    PORT=$(docker_port "$CID" "$internal_port/tcp" || true)
    
    if [ -z "$PORT" ]; then
        echo "No port mapping for $service_name. Logs:"
        docker logs "$CID" 2>&1 | tail -n 20
        docker rm -f "$CID" >/dev/null 2>&1 || true
        return
    fi
    
    echo "$service_name running at http://localhost:$PORT"
    
    # Run python test
    export TEST_PORT="$PORT"
    export TEST_NAME="$service_name"
    export TEST_KEY="$file_key"
    
    uvx --with requests --with pillow --with numpy python - <<'PY'
import os, requests, io, time, sys
from PIL import Image
import numpy as np

base_url = f"http://localhost:{os.environ['TEST_PORT']}"
name = os.environ['TEST_NAME']
key = os.environ['TEST_KEY']

print(f"Checking health for {name} at {base_url}...")
health_ok = False
for _ in range(10):
    try:
        # Try /health (GET)
        r = requests.get(f"{base_url}/health", timeout=2)
        if r.status_code == 200:
            health_ok = True
            break
        # If 404 or 405, try /healthz (GET) or /health (POST)
        if r.status_code in [404, 405]:
            r_z = requests.get(f"{base_url}/healthz", timeout=2)
            if r_z.status_code == 200:
                health_ok = True
                r = r_z
                break
            r_post = requests.post(f"{base_url}/health", timeout=2)
            if r_post.status_code == 200:
                health_ok = True
                r = r_post
                break
        
        print(f"Health: {r.status_code} {r.text[:100]}")
    except Exception as e:
        print(f"Health check retry: {e}")
    time.sleep(1)

if not health_ok:
    print("Health check failed permanently.")
    sys.exit(1)

print(f"Sending predict request...")
img = Image.fromarray(np.random.randint(0,255,(224,224,3),dtype='uint8'))
buf = io.BytesIO(); img.save(buf, format='JPEG')
img_bytes = buf.getvalue()

# Send list of files
files = [(key, ('test.jpg', img_bytes, 'image/jpeg'))]

try:
    r = requests.post(f"{base_url}/predict", files=files, timeout=10)
    print(f"Predict: {r.status_code}")
    if r.status_code == 200:
        print(f"Success! Response: {r.text[:200]}...")
    else:
        print(f"Failed: {r.text[:500]}")
except Exception as e:
    print(f"Predict failed: {e}")
PY

    echo "Logs for $service_name (tail):"
    docker logs "$CID" 2>&1 | tail -n 10
    
    echo "Stopping $service_name..."
    docker rm -f "$CID" >/dev/null 2>&1 || true
    echo "Done with $service_name"
    echo "================================================"
}

run_test "fastapi" "ml-benchmark/fastapi-mobilenet:latest" 8000 "files"
run_test "bentoml" "ml-benchmark/bentoml-mobilenet:latest" 3000 "files"
run_test "rayserve" "ml-benchmark/rayserve-mobilenet:latest" 8000 "files"