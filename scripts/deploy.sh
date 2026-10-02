#!/usr/bin/env bash
# Atomically release a chart, then prove it serves traffic.
# Usage: scripts/deploy.sh <release> <namespace> <image-tag> [extra helm args...]
set -Eeuo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <release> <namespace> <image-tag> [extra helm args...]" >&2
  exit 2
fi

readonly RELEASE="$1"
readonly NAMESPACE="$2"
readonly IMAGE_TAG="$3"
shift 3

echo "deploying ${RELEASE} into ${NAMESPACE} with image tag ${IMAGE_TAG}"

# Mirror the MinIO credentials (source of truth: tofu-managed secret in data)
# into the release namespace so the model-files init container can authenticate.
MINIO_USER="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-user}' | base64 -d)"
MINIO_PASS="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-password}' | base64 -d)"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" create secret generic minio-model \
  --from-literal=root-user="${MINIO_USER}" \
  --from-literal=root-password="${MINIO_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "${RELEASE}" deploy/charts/model-api \
  --namespace "${NAMESPACE}" --create-namespace \
  --set "image.tag=${IMAGE_TAG}" \
  "$@" \
  --atomic --wait --timeout 5m

echo "release ${RELEASE} deployed; running smoke checks"
scripts/smoke.sh "${NAMESPACE}" "${RELEASE}"
