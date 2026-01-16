SHELL := /bin/bash
.ONESHELL:

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts

# Public targets
.PHONY: benchmark setup build deploy loadtest cleanup test

benchmark: setup loadtest

setup:
	bash "$(SCRIPTS)/setup.sh"

# Run smoke tests per service in isolation to avoid dependency overlap
test:
	uvx --with numpy --with pillow --with requests --with httpx --with fastapi --with uvicorn --with tensorflow==2.15.0 --with keras==2.15.0 --with python-multipart pytest tests/test_smoke_fastapi.py
	uvx --with numpy --with pillow --with bentoml==1.4.33 --with tensorflow==2.15.0 pytest tests/test_smoke_bentoml.py
	uvx --with numpy --with pillow --with tensorflow==2.15.0 --with ray --with fastapi --with uvicorn --with python-multipart pytest tests/test_smoke_rayserve.py

build: test
	bash "$(SCRIPTS)/build-images.sh"
	bash "$(SCRIPTS)/test-containers.sh"

deploy: 
	bash "$(SCRIPTS)/deploy-k8s.sh"

loadtest: 
	bash "$(SCRIPTS)/automated-loadtest.sh"

cleanup:
	bash "$(SCRIPTS)/cleanup.sh"


