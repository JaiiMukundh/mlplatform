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

# Mirror the Postgres app credentials (source of truth: tofu-managed secret in
# data) as a full SQLAlchemy URL so prediction rows reach prediction_log (P6.7).
PG_USER="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.username}' | base64 -d)"
PG_PASS="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.postgres-password}' | base64 -d)"
kubectl -n "${NAMESPACE}" create secret generic postgres-app \
  --from-literal=database-url="postgresql+psycopg://${PG_USER}:${PG_PASS}@postgres.data.svc:5432/mlp" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "${RELEASE}" deploy/charts/model-api \
  --namespace "${NAMESPACE}" --create-namespace \
  --set "image.tag=${IMAGE_TAG}" \
  "$@" \
  --atomic --wait --timeout 5m

echo "release ${RELEASE} deployed; running smoke checks"
if [[ "${RELEASE}" == "model-api-staging" ]]; then
  # The staging release serves host port 8081 (NodePort 30081); the default
  # smoke URL would silently test production instead.
  scripts/smoke.sh "${NAMESPACE}" "${RELEASE}" "http://localhost:8081"
else
  scripts/smoke.sh "${NAMESPACE}" "${RELEASE}"
fi
