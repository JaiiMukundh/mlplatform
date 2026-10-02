#!/usr/bin/env bash
# Drive sustained load and watch HPA scale the deployment.
# Usage: scripts/chaos_load.sh [namespace] [release] [base-url]
set -Eeuo pipefail

readonly NAMESPACE="${1:-serving}"
readonly RELEASE="${2:-model-api}"
readonly BASE_URL="${3:-http://localhost:8080}"

echo "chaos-load: ${RELEASE}.${NAMESPACE} via ${BASE_URL} (180s at ~40rps)"
uv run python scripts/traffic.py --rps 40 --duration 180 --url "${BASE_URL}"
echo "chaos-load: watching HPA"
kubectl get hpa -n "${NAMESPACE}"
