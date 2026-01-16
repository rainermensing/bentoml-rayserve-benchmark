#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "Building Docker images for ML benchmark"

build_if_exists() {
	local name="$1"
	local dockerfile="$2"
	local context="$3"
	if [ -f "$dockerfile" ]; then
		echo "Building image ml-benchmark/${name}:latest from ${dockerfile}"
		docker build -t "ml-benchmark/${name}:latest" -f "$dockerfile" $context
	else
		echo "Skipping ${name}: ${dockerfile} not found"
	fi
}

## BentoML build: only run `bentoml build` via uvx if bentofile.yaml exists and
## contains a `service:` entry. An empty or incomplete bentofile will cause
## `bentoml build` to fail (observed previously), so we detect that and skip
## the Bento build in that case.
if [ -f "bentoml_service/bentofile.yaml" ] || [ -f "bentoml_service/bentofile.yml" ]; then
	BENTOFILE=""
	if [ -f "bentoml_service/bentofile.yaml" ]; then
		BENTOFILE="bentoml_service/bentofile.yaml"
	else
		BENTOFILE="bentoml_service/bentofile.yml"
	fi

	if grep -Eiq "^\s*service\s*:" "$BENTOFILE"; then
		echo "Found bentoml bentofile with 'service' entry — building bento with BentoML via uvx"
		# Build the bento inside uvx to ensure isolated deps (Python 3.11 + TensorFlow)
		# We use the bentofile at bentoml_service/bentofile.yaml but set the build context to root (.)
		# Set PYTHONPATH to root so bentoml_service is findable as a package
		BENTO_TAG=$(PYTHONPATH=. uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml build -f "$BENTOFILE" . -o tag 2>/dev/null || true)
		# Strip potential __tag__: prefix
		BENTO_TAG=${BENTO_TAG#__tag__:}
		
		if [ -n "$BENTO_TAG" ]; then
			echo "Built Bento: $BENTO_TAG"
			echo "Containerizing Bento into Docker image ml-benchmark/bentoml-mobilenet:latest"
			# Remove existing image to prevent dangling <none> images
			if docker image inspect ml-benchmark/bentoml-mobilenet:latest >/dev/null 2>&1; then
				echo "Removing existing ml-benchmark/bentoml-mobilenet:latest..."
				docker rmi ml-benchmark/bentoml-mobilenet:latest || true
			fi
			# Use --opt load to place the built image into the local Docker daemon
			uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml containerize "$BENTO_TAG" -t ml-benchmark/bentoml-mobilenet:latest --opt load || true
		else
			echo "bentoml build did not produce a tag; attempting fallback build from source"
			# Try building from source directory as a fallback
			FALLBACK_TAG=$(uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml build . -o tag 2>/dev/null || true)
			FALLBACK_TAG=${FALLBACK_TAG#__tag__:}
			
			if [ -n "$FALLBACK_TAG" ]; then
				echo "Fallback built Bento: $FALLBACK_TAG"
				# Remove existing image to prevent dangling <none> images
				if docker image inspect ml-benchmark/bentoml-mobilenet:latest >/dev/null 2>&1; then
					echo "Removing existing ml-benchmark/bentoml-mobilenet:latest..."
					docker rmi ml-benchmark/bentoml-mobilenet:latest || true
				fi
				uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml containerize "$FALLBACK_TAG" -t ml-benchmark/bentoml-mobilenet:latest --opt load || true
			else
				echo "Fallback build also failed; skipping containerize"
			fi
		fi
	else
		echo "bentofile exists but does not contain 'service:' — skipping bentoml build"
		echo "If you want to build a Bento, add a 'service:' entry to bentoml/bentofile.yaml"
	fi
else
	echo "No bentofile found; skipping Bento build"
fi

# FastAPI image
build_if_exists "fastapi-mobilenet" "fastapi/Dockerfile" "."

# Ray Serve image
if [ -f "rayserve/app.py" ]; then
    echo "Generating Ray Serve config..."
    # We use uv run to ensure we have the correct ray version and dependencies to import app.py
    uv run --with "ray[serve]==2.6.0" --with "fastapi" --with "tensorflow==2.15.0" --with "pydantic<2.0.0" --with "numpy" --with "Pillow" --with "python-multipart" -- bash -c "cd rayserve && serve build app:graph -o serve_config.yaml" || echo "Warning: Failed to generate serve_config.yaml, using existing one if present."
fi
build_if_exists "rayserve-mobilenet" "rayserve/Dockerfile" "."

# Locust service image
build_if_exists "locust-service" "locust_service/Dockerfile" "."

echo "Docker image build step complete"
