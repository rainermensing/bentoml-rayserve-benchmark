SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts

# Generic loadtest parameters
DURATION_PER_LEVEL ?= 10
CONCURRENCY_LEVELS ?= 10 20 40 80 
REPLICAS ?= 2
SERVICE ?= all
# Locust parameters
LOCUST_DURATION ?= 60s
# Set to 40 for stable local benchmarking
LOCUST_USERS ?= 80
LOCUST_SPAWN_RATE ?= 2

# Public targets
.PHONY: benchmark setup build deploy loadtest process locust cleanup test

benchmark: setup loadtest

setup:
	bash "$(SCRIPTS)/setup.sh"

# Run smoke tests per service in isolation to avoid dependency overlap
test:
	uvx --python 3.11 --with numpy --with pillow --with requests --with httpx --with "fastapi==0.128.0" --with uvicorn --with tensorflow==2.16.1 --with python-multipart pytest tests/test_smoke_fastapi.py
	uvx --python 3.11 --with numpy --with pillow --with bentoml==1.4.33 --with tensorflow==2.16.1 pytest tests/test_smoke_bentoml.py
	uvx --python 3.11 --with numpy --with pillow --with tensorflow==2.16.1 --with "ray[serve]==2.53.0" --with "fastapi==0.128.0" --with uvicorn --with python-multipart pytest tests/test_smoke_rayserve.py

build: test
	bash "$(SCRIPTS)/build-images.sh"
	bash "$(SCRIPTS)/test-containers.sh"

deploy: 
	bash "$(SCRIPTS)/deploy-k8s.sh" all $(REPLICAS)

loadtest: 
	bash "$(SCRIPTS)/generic/automated-loadtest.sh" $(DURATION_PER_LEVEL) "$(CONCURRENCY_LEVELS)" $(REPLICAS) $(SERVICE)

process:
	bash "$(SCRIPTS)/generic/process-results.sh" "$(CONCURRENCY_LEVELS)" $(DURATION_PER_LEVEL)

locust: 
	bash "$(SCRIPTS)/locust/run-locust-tests.sh" $(LOCUST_DURATION) $(LOCUST_USERS) $(LOCUST_SPAWN_RATE) $(REPLICAS)

process-locust:
	bash "$(SCRIPTS)/locust/process-locust-results.sh"

cleanup:
	bash "$(SCRIPTS)/cleanup.sh"


