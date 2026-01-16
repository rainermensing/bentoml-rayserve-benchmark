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
if [ -f "bentoml/bentofile.yaml" ] || [ -f "bentoml/bentofile.yml" ]; then
	BENTOFILE=""
	if [ -f "bentoml/bentofile.yaml" ]; then
		BENTOFILE="bentoml/bentofile.yaml"
	else
		BENTOFILE="bentoml/bentofile.yml"
	fi

	if grep -Eiq "^\s*service\s*:" "$BENTOFILE"; then
		echo "Found bentoml bentofile with 'service' entry — building bento with BentoML via uvx"
		pushd bentoml >/dev/null
		# Build the bento inside uvx to ensure isolated deps (Python 3.10 + TensorFlow)
		# Capture the bento tag output so we can containerize it.
		BENTO_TAG=$(uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml build -o tag 2>/dev/null || true)
		if [ -n "$BENTO_TAG" ]; then
			echo "Built Bento: $BENTO_TAG"
			echo "Containerizing Bento into Docker image ml-benchmark/bentoml-mobilenet:latest"
			# Use --load to place the built image into the local Docker daemon
			uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml containerize "$BENTO_TAG" -t ml-benchmark/bentoml-mobilenet:latest --load || true
		else
			echo "bentoml build did not produce a tag; attempting fallback build from source"
			# Try building from source directory as a fallback
			FALLBACK_TAG=$(uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml build . -o tag 2>/dev/null || true)
			if [ -n "$FALLBACK_TAG" ]; then
				echo "Fallback built Bento: $FALLBACK_TAG"
				uvx --python 3.11 --with bentoml==1.4.33 --with tensorflow==2.15.0 --with numpy --with pillow bentoml containerize "$FALLBACK_TAG" -t ml-benchmark/bentoml-mobilenet:latest --load || true
			else
				echo "Fallback build also failed; skipping containerize"
			fi
		fi
		popd >/dev/null
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
build_if_exists "rayserve-mobilenet" "rayserve/Dockerfile" "."

# Loadtest image
build_if_exists "loadtest" "loadtest/Dockerfile" "."

echo "Docker image build step complete"
