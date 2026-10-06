SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap preflight lint fmt test build up down deploy forward seed-data train \
	traffic demo-infra demo-model reset-demo tofu-local-apply tofu-local-destroy \
	build-training publish-feast-data feast-apply feast-materialize feast-verify \
	train-mlflow gate-candidate feast-rematerialize model-release-local \
	deploy-monitor e2e deploy-all

help: ## Show the supported project commands.
	@awk 'BEGIN {FS = ":.*## "; printf "MLPlatform targets:\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Verify the laptop prerequisites and record their versions.
	@bash ops/scripts/bootstrap.sh

preflight: ## Verify host kernel limits required by kind.
	@bash ops/scripts/archive/check_host.sh

lint: ## Lint all implemented Python code.
	@uv run ruff check .
	@uv run ruff format --check .

fmt: ## Format all implemented Python code.
	@uv run ruff check --fix .
	@uv run ruff format .

test: ## Run the unit test suite and coverage gate.
	@uv run pytest --cov=mlp_common --cov=model_api --cov-report=term-missing

build: ## Build local service images.
	@hadolint infra/docker/model_api.Dockerfile
	@docker build --file infra/docker/model_api.Dockerfile \
		--tag localhost:5001/model-api:dev .

build-training: ## Build and push the training/Feast image.
	@hadolint infra/docker/training.Dockerfile
	@docker build --file infra/docker/training.Dockerfile \
		--tag localhost:5001/training:dev .
	@docker push localhost:5001/training:dev

publish-feast-data: ## Publish Parquet data to the MinIO feast-offline bucket.
	@bash ops/scripts/publish_feast_data.sh

feast-apply: build-training publish-feast-data ## Apply the Feast definitions (in-cluster Job).
	@bash ops/scripts/run_job.sh infra/deploy/feast/apply-job.yaml

feast-materialize: feast-apply ## Materialize Feast features into the Redis online store.
	@bash ops/scripts/run_job.sh infra/deploy/feast/materialize-job.yaml

feast-rematerialize: ## Rewrite the full feature window (recovery after a Redis wipe).
	@bash ops/scripts/run_job.sh infra/deploy/feast/rematerialize-job.yaml

feast-verify: ## Verify the Feast offline and online stores match (P6.3).
	@bash ops/scripts/run_job.sh infra/deploy/feast/verify-job.yaml

train-mlflow: build-training ## Train via Feast and register in MLflow (P6.4).
	@bash ops/scripts/train_mlflow.sh

gate-candidate: build-training ## Score a candidate version (VERSION=N) in-cluster (P7.1).
	@VERSION="${VERSION:?set VERSION=N}" bash ops/scripts/run_gate.sh

model-release-local: ## Release a candidate to prod (VERSION=N, TAG=dev) (P7.3).
	@bash ops/scripts/model_release_local.sh "${VERSION:?set VERSION=N}" "${TAG:-dev}"

deploy-monitor: ## Build and deploy the drift monitor and retrain platform (P8).
	@bash ops/scripts/deploy_monitor.sh

e2e: ## Run the local serving and self-healing end-to-end tests.
	@MLP_RUN_E2E=1 MLP_E2E_RUN_DEMO=1 uv run pytest tests/e2e -q

up: ## Build the complete local platform from scratch.
	@bash ops/scripts/archive/check_host.sh
	@tofu -chdir=infra/envs/local init
	@tofu -chdir=infra/envs/local apply -auto-approve \
		-target=module.registry -target=module.cluster
	@bash ops/scripts/archive/push_bootstrap_images.sh
	@tofu -chdir=infra/envs/local apply -auto-approve
	@bash ops/scripts/bootstrap-post.sh

deploy-all: ## Deploy all workloads and seed baselines after cluster creation (P9.2).
	@bash ops/scripts/deploy_all.sh

down: ## Destroy the local platform.
	@tofu -chdir=infra/envs/local destroy -auto-approve || true
	@kind delete cluster --name mlp || true
	@docker rm -f kind-registry || true

deploy: ## Deploy model-api to the local cluster.
	@bash ops/scripts/deploy.sh model-api serving dev

forward: ## Open local port-forwards when NodePorts are unavailable.
	@bash ops/scripts/forward.sh

seed-data: ## Generate deterministic synthetic model data.
	@uv run python -m ml.data.generate --out data --seed 42

train: ## Train and evaluate a model locally.
	@uv run python -m ml.train --mode file --data-dir data --artifacts-dir artifacts

traffic: ## Generate prediction traffic.
	@uv run python ops/scripts/traffic.py --rps 10 --duration 30 --url http://localhost:8080

demo-infra: ## Demonstrate Kubernetes and alert self-healing.
	@bash ops/scripts/chaos_alert.sh

demo-model: ## Demonstrate drift-triggered retraining and release.
	@bash ops/scripts/retrain_and_release.sh

reset-demo: ## Restore the repeatable demo baseline.
	@uv run python ops/scripts/reset_demo.py

tofu-local-apply: ## Apply the local OpenTofu stack.
	@tofu -chdir=infra/envs/local apply -auto-approve

tofu-local-destroy: ## Destroy the local OpenTofu stack.
	@tofu -chdir=infra/envs/local destroy -auto-approve

aws-init: ## Initialize OpenTofu AWS configuration without remote state.
	@tofu -chdir=infra/envs/aws init -backend=false

aws-validate: ## Validate OpenTofu AWS configuration syntax.
	@tofu -chdir=infra/envs/aws validate

aws-plan: ## Run OpenTofu plan against AWS (requires AWS credentials; non-billable).
	@tofu -chdir=infra/envs/aws plan

aws-apply: ## [HUMAN] Apply AWS infrastructure (strictly human action under P9.6).
	@echo "========================================================================"
	@echo "STOP: AWS apply creates billable cloud resources."
	@echo "Per AGENTS.md Rule 12 and P9.6, this step must be run by a HUMAN."
	@echo "Follow the step-by-step checklist in ops/docs/archive/aws-port.md."
	@echo "When ready, execute manually: tofu -chdir=infra/envs/aws apply"
	@echo "========================================================================"
	@exit 1

aws-destroy: ## [HUMAN] Destroy AWS infrastructure.
	@tofu -chdir=infra/envs/aws destroy

ui: ## Launch the Central Management and Demo Dashboard (http://localhost:8050).
	@echo "Starting Central Management UI on http://localhost:8050 ..."
	@uv run python -m ops.ui.app
