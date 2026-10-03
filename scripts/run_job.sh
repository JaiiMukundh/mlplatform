#!/usr/bin/env bash
# Recreate an idempotent Job and fail promptly with logs on terminal failure.
set -Eeuo pipefail
manifest="${1:?job manifest required}"
namespace="${2:-data}"
name="$(kubectl create --dry-run=client -f "$manifest" -o jsonpath='{.metadata.name}')"
kubectl -n "$namespace" delete job "$name" --ignore-not-found --wait=true
kubectl apply -f "$manifest"
deadline=$((SECONDS + ${JOB_TIMEOUT_SECONDS:-600}))
while ((SECONDS < deadline)); do
  status="$(kubectl -n "$namespace" get job "$name" -o json)"
  if jq -e '.status.conditions[]? | select(.type == "Complete" and .status == "True")' <<<"$status" >/dev/null; then
    kubectl -n "$namespace" logs "job/$name" --all-containers=true
    echo "job/$name completed"
    exit 0
  fi
  if jq -e '.status.conditions[]? | select(.type == "Failed" and .status == "True")' <<<"$status" >/dev/null; then
    break
  fi
  sleep 2
done
kubectl -n "$namespace" logs "job/$name" --all-containers=true --tail=100 || true
kubectl -n "$namespace" get pods -l "job-name=$name" -o wide
printf 'ERROR: job/%s failed or timed out\n' "$name" >&2
exit 1
