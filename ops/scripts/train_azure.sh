#!/usr/bin/env bash
# Train via Feast + MLflow on AKS and register the new model version.
# [HUMAN] ONLY — runs against the AKS kubectl context (billable cluster).
# Usage: TAG=v1.0.0 TRIGGER=manual bash ops/scripts/train_azure.sh
# Idempotent: the previous train-mlflow Job is deleted before a new one runs.
set -Eeuo pipefail

readonly TAG="${TAG:-v1.0.0}"
readonly TRIGGER="${TRIGGER:-manual}"
readonly GIT_SHA="$(git rev-parse HEAD)"
readonly RENDERED="/tmp/train-job-azure.rendered.yaml"
SHUFFLE_FLAG=""
if [[ "${SHUFFLE:-0}" == "1" ]]; then
  SHUFFLE_FLAG="--shuffle-labels"
fi

ACR_LOGIN="${ACR_LOGIN:-$(terraform -chdir=infra/envs/azure output -raw acr_login_server)}"
export ACR_LOGIN

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRAIN_YAML="${REPO_ROOT}/infra/deploy/training/train-job-azure.yaml"
RUN_JOB_SCRIPT="${REPO_ROOT}/ops/scripts/run_job.sh"

sed -e "s|__ACR_LOGIN__|${ACR_LOGIN}|g" -e "s|__TAG__|${TAG}|g" \
  -e "s/__TRIGGER__/${TRIGGER}/" -e "s/__GIT_SHA__/${GIT_SHA}/" \
  -e "s/__SHUFFLE_FLAG__/${SHUFFLE_FLAG}/" \
  "${TRAIN_YAML}" >"${RENDERED}"
JOB_TIMEOUT_SECONDS="${JOB_TIMEOUT_SECONDS:-1200}" bash "${RUN_JOB_SCRIPT}" \
  "${RENDERED}" data
