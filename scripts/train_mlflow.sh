#!/usr/bin/env bash
# Train via Feast + MLflow in-cluster and register the new model version.
# Usage: TRIGGER=manual|drift bash scripts/train_mlflow.sh
# Idempotent: the previous train-mlflow Job is deleted before a new one runs.
set -Eeuo pipefail

readonly TRIGGER="${TRIGGER:-manual}"
readonly GIT_SHA="$(git rev-parse HEAD)"
readonly RENDERED="/tmp/train-job.rendered.yaml"

sed -e "s/__TRIGGER__/${TRIGGER}/" -e "s/__GIT_SHA__/${GIT_SHA}/" \
  deploy/training/train-job.yaml >"${RENDERED}"
JOB_TIMEOUT_SECONDS="${JOB_TIMEOUT_SECONDS:-1200}" bash scripts/run_job.sh \
  "${RENDERED}" data
