#!/usr/bin/env bash
# Prove a released model-api serves traffic through its cluster Service.
# Usage: scripts/smoke.sh [namespace] [release] [base-url]
set -Eeuo pipefail

readonly NAMESPACE="${1:-serving}"
readonly RELEASE="${2:-model-api}"
readonly BASE_URL="${3:-http://model-api.serving.svc:8080}"

echo "smoke: ${RELEASE}.${NAMESPACE} via ${BASE_URL}"
auth_header=()
if [[ -n "${MODEL_API_TOKEN:-}" ]]; then
  auth_header=(-H "Authorization: Bearer ${MODEL_API_TOKEN}")
fi
sleep 2

ready="$(curl --retry 5 --retry-connrefused --retry-all-errors --retry-delay 1 -s -o /dev/null -w '%{http_code}' "${BASE_URL}/readyz")"
if [[ "${ready}" != "200" ]]; then
  echo "smoke FAIL: /readyz returned ${ready}" >&2
  exit 1
fi
echo "smoke: /readyz 200"

prediction="$(curl --retry 5 --retry-connrefused --retry-all-errors --retry-delay 1 -s -X POST "${BASE_URL}/predict" -H 'content-type: application/json' "${auth_header[@]}" -d '{"customer_ids":[1,2,3]}')"
echo "smoke: /predict -> ${prediction}"
count="$(echo "${prediction}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["predictions"]))')"
if [[ "${count}" != "3" ]]; then
  echo "smoke FAIL: expected 3 predictions, got ${count}" >&2
  exit 1
fi

echo "smoke PASS: ${RELEASE} serves predictions via ${BASE_URL}"
