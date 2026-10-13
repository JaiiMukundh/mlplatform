SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap preflight lint fmt test build up down deploy forward seed-data train \
	traffic demo-infra demo-model reset-demo terraform-local-apply terraform-local-destroy \
	build-training publish-feast-data feast-apply feast-materialize feast-verify \
	train-mlflow gate-candidate feast-rematerialize model-release-local \
	deploy-monitor e2e deploy-all azure-init azure-validate azure-plan azure-apply azure-destroy \
	deploy-azure destroy-azure azure-preflight deploy-azure-full train-azure \
	azure-sleep azure-wake azure-kill-compute ui

help: ## Show the supported project commands.
	@awk 'BEGIN {FS = ":.*## "; printf "MLPlatform targets:\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Verify the laptop prerequisites and record their versions.
	@bash ops/scripts/bootstrap.sh

preflight: ## Verify host kernel limits required by kind.
	@test $$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0) -ge 524288 || (echo "Kernel limits too low. Run: sudo sysctl -w fs.inotify.max_user_watches=524288" && exit 1)

lint: ## Lint all implemented Python code.
	@uv run ruff check .
	@uv run ruff format --check .

fmt: ## Format all implemented Python code.
	@uv run ruff check --fix .
	@uv run ruff format .

test: ## Run the unit test suite and coverage gate.
	@uv run pytest --cov=mlp_common --cov=model_api --cov-report=term-missing

.PHONY: check-infra secret-scan github-login github-push
check-infra: ## Validate Terraform, Helm charts, and shell syntax without deploying.
	@terraform fmt -check -recursive infra
	@for env in local azure; do terraform -chdir=infra/envs/$$env init -backend=false -input=false -lockfile=readonly && terraform -chdir=infra/envs/$$env validate || exit 1; done
	@for chart in infra/deploy/charts/*; do helm lint "$$chart" || exit 1; done
	@for script in ops/scripts/*.sh infra/modules/*/files/*.sh; do bash -n "$$script" || exit 1; done

secret-scan: ## Scan Git history and staged changes for credentials (redacted output).
	@gitleaks git --redact --no-banner
	@gitleaks git --redact --no-banner --pre-commit --staged

github-login: ## Authenticate GitHub CLI and Git without sharing credentials.
	@gh auth login --hostname github.com --git-protocol https --web
	@gh auth setup-git

github-push: ## Push the verified current branch to origin without force.
	@git push --set-upstream origin HEAD

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
	@test $$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0) -ge 524288 || (echo "Kernel limits too low. Run: sudo sysctl -w fs.inotify.max_user_watches=524288" && exit 1)
	@terraform -chdir=infra/envs/local init
	@terraform -chdir=infra/envs/local apply -auto-approve \
		-target=module.registry -target=module.cluster
	@docker build --file infra/docker/mlflow.Dockerfile --tag localhost:5001/mlflow:dev . && docker push localhost:5001/mlflow:dev
	@terraform -chdir=infra/envs/local apply -auto-approve
	@bash ops/scripts/bootstrap-post.sh

deploy-all: ## Deploy all workloads and seed baselines after cluster creation (P9.2).
	@bash ops/scripts/deploy_all.sh

down: ## Destroy the local platform.
	@terraform -chdir=infra/envs/local destroy -auto-approve || true
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

terraform-local-apply: ## Apply the local Terraform stack.
	@terraform -chdir=infra/envs/local apply -auto-approve

terraform-local-destroy: ## Destroy the local Terraform stack.
	@terraform -chdir=infra/envs/local destroy -auto-approve

azure-init: ## Initialize Terraform Azure provider (no credentials required).
	@terraform -chdir=infra/envs/azure init -backend=false

azure-validate: ## Validate Terraform Azure configuration syntax.
	@terraform -chdir=infra/envs/azure validate

azure-plan: ## Run Terraform plan against Azure (requires Azure credentials or az login).
	@terraform -chdir=infra/envs/azure plan

azure-apply: ## [HUMAN] Apply Azure infrastructure (creates billable resources).
	@echo "========================================================================"
	@echo "STOP: Azure apply creates billable cloud resources."
	@echo "Per AGENTS.md Rule 12 and P9.6, this step must be run by a HUMAN."
	@echo "Follow the step-by-step checklist in ops/docs/azure-port.md."
	@echo "When ready, execute manually: bash ops/scripts/deploy_azure.sh"
	@echo "========================================================================"
	@exit 1

azure-destroy: ## Tear down complete Azure infrastructure to stop billing.
	@bash ops/scripts/destroy_azure.sh

deploy-azure: ## Run complete Azure deployment (Terraform + rsync + kind).
	@bash ops/scripts/deploy_azure.sh

destroy-azure: ## Tear down complete Azure deployment to stop billing.
	@bash ops/scripts/destroy_azure.sh

azure-preflight: ## Read-only Azure eligibility check (needs az login, spends nothing).
	@bash ops/scripts/azure_preflight.sh

deploy-azure-full: ## [HUMAN] Full platform on AKS incl. training (billable).
	@echo "========================================================================"
	@echo "STOP: Full AKS deployment creates billable cloud resources."
	@echo "Per AGENTS.md Rule 12 this step must be run by a HUMAN."
	@echo "First: make azure-preflight (or bash ops/scripts/azure_preflight.sh)."
	@echo "When ready, execute manually: TAG=v1.0.0 bash ops/scripts/deploy_azure_full.sh"
	@echo "========================================================================"
	@exit 1

train-azure: ## [HUMAN] Train on AKS via Feast+MLflow (needs AKS context).
	@echo "STOP: runs a training Job on billable AKS. Execute manually:"
	@echo "  TAG=v1.0.0 TRIGGER=manual bash ops/scripts/train_azure.sh"
	@exit 1

azure-sleep: ## [HUMAN] Stop AKS (compute ~$$0/hr, registry/state kept).
	@echo "STOP: changes billable state. Execute manually:"
	@echo "  bash ops/scripts/azure_compute.sh sleep"
	@exit 1

azure-wake: ## [HUMAN] Start AKS again after sleep.
	@echo "STOP: changes billable state. Execute manually:"
	@echo "  bash ops/scripts/azure_compute.sh wake"
	@exit 1

azure-kill-compute: ## [HUMAN] Destroy AKS only (ACR/Blob/DB persist).
	@echo "STOP: destroys the cluster; in-cluster state is lost (see azure-port.md)."
	@echo "Execute manually after reviewing the plan:"
	@echo "  terraform -chdir=infra/envs/azure plan -destroy -target=module.cluster"
	@echo "  terraform -chdir=infra/envs/azure destroy -target=module.cluster"
	@exit 1

ui: ## Launch the Central Management and Demo Dashboard (http://localhost:8050).
	@echo "Starting Central Management UI on http://localhost:8050 ..."
	@uv run python -m ops.ui.app
