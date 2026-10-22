#!/usr/bin/env bash
# Roll an already Terraform-managed AKS model API deployment to one model version.
set -Eeuo pipefail
[[ "${DEPLOY_TARGET:-}" == azure ]] || { echo "DEPLOY_TARGET=azure is required" >&2; exit 2; }
: "${MODEL_API_REPOSITORY:?set the ACR model API repository}"
[[ $# == 4 ]] || { echo "usage: $0 <deployment> <namespace> <image-tag> <model-version>" >&2; exit 2; }

readonly DEPLOYMENT="$1"
readonly NAMESPACE="$2"
readonly IMAGE_TAG="$3"
readonly VERSION="$4"
[[ "${VERSION}" =~ ^[0-9]+$ ]] || { echo "model version must be numeric" >&2; exit 2; }

kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT}" >/dev/null
kubectl -n "${NAMESPACE}" set image "deployment/${DEPLOYMENT}" \
  "api=${MODEL_API_REPOSITORY}:${IMAGE_TAG}"
kubectl -n "${NAMESPACE}" set env "deployment/${DEPLOYMENT}" \
  "MODEL_VERSION=${VERSION}"
kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=5m

[[ "${SKIP_SMOKE:-0}" != 1 ]] || exit 0
if [[ "${NAMESPACE}" == staging ]]; then
  bash scripts/smoke.sh "${NAMESPACE}" "${DEPLOYMENT}" \
    "${STAGING_SMOKE_URL:-http://model-api-staging.staging.svc:8080}"
else
  bash scripts/smoke.sh "${NAMESPACE}" "${DEPLOYMENT}" \
    "${PROD_SMOKE_URL:-http://model-api.serving.svc:8080}"
fi
