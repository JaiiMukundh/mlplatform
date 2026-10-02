SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap lint fmt test build up down deploy forward seed-data train \
	traffic demo-infra demo-model reset-demo tofu-local-apply tofu-local-destroy

help: ## Show the supported project commands.
	@awk 'BEGIN {FS = ":.*## "; printf "MLPlatform targets:\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Verify the laptop prerequisites and record their versions.
	@bash scripts/bootstrap.sh

lint: ## Lint all implemented Python code.
	@echo "TODO(P0.5): lint"

fmt: ## Format all implemented Python code.
	@echo "TODO(P0.5): fmt"

test: ## Run the unit test suite and coverage gate.
	@echo "TODO(P0.5): test"

build: ## Build local service images.
	@echo "TODO(P1.7): build"

up: ## Build the complete local platform from scratch.
	@echo "TODO(P3.5): up"

down: ## Destroy the local platform.
	@echo "TODO(P3.5): down"

deploy: ## Deploy model-api to the local cluster.
	@echo "TODO(P2.5): deploy"

forward: ## Open local port-forwards when NodePorts are unavailable.
	@echo "TODO(P3.5): forward"

seed-data: ## Generate deterministic synthetic model data.
	@echo "TODO(P1.1): seed-data"

train: ## Train and evaluate a model locally.
	@echo "TODO(P1.2): train"

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
