DOCKER_NETWORK ?= default
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help lint fmt test seed-data train publish-feast-data train-azure azure azure-check azure-plan azure-apply azure-destroy azure-kill check-infra check-actions check-charts check-images smoke-images secret-scan security tools

help: ## Show the supported project commands.
	@awk 'BEGIN {FS = ":.*## "; printf "MLPlatform targets:\n\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-22s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

lint: ## Lint all implemented Python code.
	@uv run --all-groups ruff check .
	@uv run --all-groups ruff format --check .

fmt: ## Format all implemented Python code.
	@uv run --all-groups ruff check --fix .
	@uv run --all-groups ruff format .

test: ## Run the unit test suite and coverage gate.
	@uv run --all-groups pytest --cov=mlp_common --cov=model_api --cov-report=term-missing

.PHONY: check-infra secret-scan github-login github-push tools check-actions check-charts security azure azure-check
tools: ## Install checksum-verified Linux CI tools (TOOLSET="...").
	@python3 scripts/tools.py $(or $(TOOLSET),actionlint gitleaks hadolint kubeconform trivy)

check-actions: ## Validate GitHub Actions workflows.
	@actionlint -shellcheck=""

check-charts: ## Validate rendered Kubernetes manifests and vendored CRD schemas.
	@uv run --all-groups python scripts/tools.py check-charts

.PHONY: check-images
check-images: ## Build and import-smoke all six container targets without deploying.
	@hadolint infra/Dockerfile
	@for service in model-api drift-monitor remediator training retrain mlflow dashboard; do \
		docker build --network "$(DOCKER_NETWORK)" --file infra/Dockerfile --target "$$service" --tag "mlp-check-$$service" . || exit 1; \
	done
	@$(MAKE) smoke-images

.PHONY: smoke-images
smoke-images: ## Import real service entry points and ensure models/data are absent.
	@for service in model-api drift-monitor remediator training retrain mlflow dashboard; do \
		module="$${service//-/_}.main"; \
		case "$$service" in training) module="feast, ml.train";; mlflow) module=mlflow;; dashboard) module=ui.app;; esac; \
		docker run --rm --entrypoint python "mlp-check-$$service" -c "import $$module; print('$$service entry point OK')" || exit 1; \
	done
	@docker run --rm --entrypoint sh mlp-check-model-api -c 'test ! -e /app/data/features.parquet && test ! -e /app/artifacts/model.joblib'
	@docker run --rm --entrypoint bash mlp-check-retrain -c 'helm template model-api infra/charts/model-api >/dev/null && test -r infra/jobs/gate-job.yaml && for script in scripts/*.sh; do bash -n "$$script" || exit 1; done'

security: ## Reject critical dependency vulnerabilities; report IaC findings.
	@trivy fs --scanners vuln --file-patterns "pip:training.txt" --severity CRITICAL --exit-code 1 --skip-dirs .venv,.terraform --skip-files PROGRESS.md .
	@trivy config --severity HIGH,CRITICAL --exit-code 0 infra

.PHONY: image-scan
image-scan: ## Reject critical vulnerabilities in the model-api smoke-test image.
	@trivy image --scanners vuln --severity CRITICAL --exit-code 1 mlp-check-model-api

azure-check: ## Check cloud workflow configuration and human confirmation without Azure calls.
	@bash scripts/azure.sh check

azure: ## Run a manually selected cloud operation (ACTION=plan by default).
	@bash scripts/azure.sh $(or $(ACTION),plan)
check-infra: ## Validate Azure Terraform, cloud Helm charts, and shell syntax.
	@terraform fmt -check -recursive infra
	@terraform -chdir=infra/envs/azure init -backend=false -input=false -lockfile=readonly
	@terraform -chdir=infra/envs/azure validate
	@for chart in infra/charts/*; do helm lint "$$chart" || exit 1; done
	@for script in scripts/*.sh; do bash -n "$$script" || exit 1; done

secret-scan: ## Scan Git history and staged changes for credentials (redacted output).
	@gitleaks git --redact --no-banner
	@gitleaks git --redact --no-banner --pre-commit --staged

github-login: ## Authenticate GitHub CLI and Git without sharing credentials.
	@gh auth login --hostname github.com --git-protocol https --web
	@gh auth setup-git

github-push: ## Push the verified current branch to origin without force.
	@git push --set-upstream origin HEAD

.PHONY: lock-training
lock-training: ## Refresh the fully pinned training environment while preserving constraints.
	@uv pip compile core/requirements/training.in --python-version 3.11 --constraint core/requirements/training.txt --no-header --no-annotate --output-file core/requirements/training.txt

publish-feast-data: ## Publish Parquet data to the MinIO feast-offline bucket.
	@bash scripts/publish_feast_data.sh

seed-data: ## Prepare deterministic UCI Taiwan feature snapshots.
	@uv run --all-groups python -m ml.data.generate --out data --seed 42

train: ## Train and evaluate a model locally.
	@uv run --all-groups python -m ml.train --mode file --data-dir data --artifacts-dir artifacts

azure-init: ## Initialize Terraform Azure provider (no credentials required).
	@terraform -chdir=infra/envs/azure init -backend=false

azure-validate: ## Validate Terraform Azure configuration syntax.
	@terraform -chdir=infra/envs/azure validate

azure-plan: ## Run Terraform plan against Azure (requires Azure credentials or az login).
	@$(MAKE) azure ACTION=plan

# Compatibility targets share the single Azure operations script.
azure-apply deploy-azure deploy-azure-full: ## [HUMAN] Deploy Azure (CONFIRMATION=DEPLOY).
	@$(MAKE) azure ACTION=deploy

azure-destroy destroy-azure: ## [HUMAN] Destroy Azure (CONFIRMATION=DESTROY).
	@$(MAKE) azure ACTION=destroy

azure-preflight: ## Read-only Azure eligibility check; spends nothing.
	@bash scripts/azure_preflight.sh

train-azure: ## Train on the connected AKS cluster using the shared training Job.
	@TRAINING_IMAGE="$${TRAINING_IMAGE:?set TRAINING_IMAGE to the deployed ACR training image and tag}" bash scripts/train_mlflow.sh

azure-sleep: ## [HUMAN] Stop AKS; disks and managed services still bill.
	@$(MAKE) azure ACTION=sleep

azure-wake: ## [HUMAN] Start AKS (CONFIRMATION=WAKE).
	@$(MAKE) azure ACTION=wake

azure-kill: ## Delete ALL project Azure resources, including state (CONFIRMATION=KILL).
	@$(MAKE) azure ACTION=kill

azure-kill-compute: ## Explain the safer whole-cluster sleep option.
	@echo "Use make azure-sleep to retain in-cluster data; targeted destruction is not automated."
	@exit 1

azure-connect: ## Configure passwordless GitHub Azure access (no billable resources).
	@bash scripts/azure.sh connect
