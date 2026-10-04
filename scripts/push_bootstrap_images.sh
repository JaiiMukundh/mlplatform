#!/usr/bin/env bash
# Push bootstrap images required by OpenTofu platform_services (mlflow).
# Safe to rerun.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "building and pushing mlflow:dev for platform_services"
docker build --file docker/mlflow.Dockerfile \
  --tag localhost:5001/mlflow:dev .
docker push localhost:5001/mlflow:dev
