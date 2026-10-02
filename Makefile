SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

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
	@docker build --file docker/model_api.Dockerfile \
		--tag localhost:5001/model-api:dev .

up: ## Build the complete local platform from scratch.
	@tofu -chdir=infra/envs/local init
	@tofu -chdir=infra/envs/local apply -auto-approve \
		-target=module.registry -target=module.cluster
	@tofu -chdir=infra/envs/local apply -auto-approve
	@bash scripts/bootstrap-post.sh

down: ## Destroy the local platform.
	@tofu -chdir=infra/envs/local destroy -auto-approve || true
	@kind delete cluster --name mlp || true
	@docker rm -f kind-registry || true

deploy: ## Deploy model-api to the local cluster.
	@bash scripts/deploy.sh model-api serving dev

forward: ## Open local port-forwards when NodePorts are unavailable.
	@bash scripts/forward.sh

seed-data: ## Generate deterministic synthetic model data.
	@uv run python -m ml.data.generate --out data --seed 42

train: ## Train and evaluate a model locally.
	@uv run python -m ml.train --mode file --data-dir data --artifacts-dir artifacts

traffic: ## Generate prediction traffic.
	@uv run python scripts/traffic.py --rps 10 --duration 30 --url http://localhost:8080

demo-infra: ## Demonstrate Kubernetes and alert self-healing.
	@echo "TODO(P5.7): demo-infra"

demo-model: ## Demonstrate drift-triggered retraining and release.
	@echo "TODO(P8.7): demo-model"

reset-demo: ## Restore the repeatable demo baseline.
	@echo "TODO(P8.7): reset-demo"

tofu-local-apply: ## Apply the local OpenTofu stack.
	@tofu -chdir=infra/envs/local apply -auto-approve

tofu-local-destroy: ## Destroy the local OpenTofu stack.
	@tofu -chdir=infra/envs/local destroy -auto-approve
