SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Rootless Docker on this laptop cannot resolve DNS on the default bridge, so the
# build-time network defaults to host (needed to reach PyPI). Override with
# `make build DOCKER_BUILD_NETWORK=default` on hosts with working container DNS.
DOCKER_BUILD_NETWORK ?= host

.PHONY: help bootstrap lint fmt test build up down deploy forward seed-data train \
	traffic demo-infra demo-model reset-demo tofu-local-apply tofu-local-destroy

help: ## Show the supported project commands.
	@awk 'BEGIN {FS = ":.*## "; printf "MLPlatform targets:\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Verify the laptop prerequisites and record their versions.
	@bash scripts/bootstrap.sh

lint: ## Lint all implemented Python code.
	@uv run ruff check .
	@uv run ruff format --check .

fmt: ## Format all implemented Python code.
	@uv run ruff check --fix .
	@uv run ruff format .

test: ## Run the unit test suite and coverage gate.
	@uv run pytest --cov=mlp_common --cov=model_api --cov-report=term-missing

build: ## Build local service images.
	@hadolint docker/model_api.Dockerfile
	@docker build --network=$(DOCKER_BUILD_NETWORK) --file docker/model_api.Dockerfile \
		--tag localhost:5001/model-api:dev .

up: ## Build the complete local platform from scratch.
	@echo "TODO(P3.5): up"

down: ## Destroy the local platform.
	@echo "TODO(P3.5): down"

deploy: ## Deploy model-api to the local cluster.
	@echo "TODO(P2.5): deploy"

forward: ## Open local port-forwards when NodePorts are unavailable.
	@echo "TODO(P3.5): forward"

seed-data: ## Generate deterministic synthetic model data.
	@uv run python -m ml.data.generate --out data --seed 42

train: ## Train and evaluate a model locally.
	@uv run python -m ml.train --mode file --data-dir data --artifacts-dir artifacts

traffic: ## Generate prediction traffic.
	@echo "TODO(P2.7): traffic"

demo-infra: ## Demonstrate Kubernetes and alert self-healing.
	@echo "TODO(P5.7): demo-infra"

demo-model: ## Demonstrate drift-triggered retraining and release.
	@echo "TODO(P8.7): demo-model"

reset-demo: ## Restore the repeatable demo baseline.
	@echo "TODO(P8.7): reset-demo"

tofu-local-apply: ## Apply the local OpenTofu stack.
	@echo "TODO(P3.5): tofu-local-apply"

tofu-local-destroy: ## Destroy the local OpenTofu stack.
	@echo "TODO(P3.5): tofu-local-destroy"
