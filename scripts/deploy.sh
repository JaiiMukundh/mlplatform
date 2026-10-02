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
helm upgrade --install "${RELEASE}" deploy/charts/model-api \
  --namespace "${NAMESPACE}" --create-namespace \
  --set "image.tag=${IMAGE_TAG}" \
  "$@" \
  --atomic --wait --timeout 5m

echo "release ${RELEASE} deployed; running smoke checks"
scripts/smoke.sh "${NAMESPACE}" "${RELEASE}"
