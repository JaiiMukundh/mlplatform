#!/usr/bin/env bash
# Train via Feast + MLflow in-cluster and register the new model version.
# Usage: TRIGGER=manual|drift [SHUFFLE=1] bash scripts/train_mlflow.sh
# SHUFFLE=1 permutes labels first (drill-only: AUC~=0.5 candidate for P7.4b).
# Idempotent: the previous train-mlflow Job is deleted before a new one runs.
set -Eeuo pipefail

readonly TRIGGER="${TRIGGER:-manual}"
readonly GIT_SHA="$(git rev-parse HEAD)"
readonly RENDERED="/tmp/train-job.rendered.yaml"
SHUFFLE_FLAG=""
if [[ "${SHUFFLE:-0}" == "1" ]]; then
  SHUFFLE_FLAG="--shuffle-labels"
fi

sed -e "s/__TRIGGER__/${TRIGGER}/" -e "s/__GIT_SHA__/${GIT_SHA}/" \
  -e "s/__SHUFFLE_FLAG__/${SHUFFLE_FLAG}/" \
  deploy/training/train-job.yaml >"${RENDERED}"
JOB_TIMEOUT_SECONDS="${JOB_TIMEOUT_SECONDS:-1200}" bash scripts/run_job.sh \
  "${RENDERED}" data
