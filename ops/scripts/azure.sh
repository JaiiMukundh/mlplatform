#!/usr/bin/env bash
# One Azure interface: plan/deploy/verify/release/sleep/wake/destroy.
# Billable/destructive operations require an explicit human workflow confirmation.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
WORKFLOW_ACTION="${ACTION:-plan}"
ACTION="${1:-plan}"
TF=(terraform -chdir=infra/envs/azure)

check() {
  for key in ARM_CLIENT_ID ARM_TENANT_ID ARM_SUBSCRIPTION_ID TF_STATE_ACCOUNT TF_VAR_kubernetes_version TF_VAR_budget_email; do
    [[ -n "${!key:-}" ]] || { echo "Missing GitHub Azure variable: ${key}" >&2; exit 1; }
  done
  case "${ACTION:-plan}" in
    deploy|wake|destroy)
      [[ "${CONFIRMATION:-}" == "${ACTION^^}" ]] || { echo "Human confirmation must be ${ACTION^^}" >&2; exit 1; } ;;
    release)
      [[ "${VERSION:-}" =~ ^[0-9]+$ ]] || { echo "Release VERSION must be a numeric MLflow version" >&2; exit 1; } ;;
    check|plan|verify|sleep|init) ;;
    *) echo "Unknown Azure action: ${ACTION}" >&2; exit 2 ;;
  esac
}
# The check command validates the selected workflow ACTION before authenticating.
if [[ "${ACTION}" == check ]]; then ACTION="${WORKFLOW_ACTION}"; check; exit; fi
check
"${TF[@]}" init -input=false -lockfile=readonly \
  -backend-config="storage_account_name=${TF_STATE_ACCOUNT}" \
  -backend-config="container_name=tfstate" -backend-config="key=mlplatform.tfstate" \
  -backend-config="use_azuread_auth=true" -backend-config="use_oidc=true"
[[ "${ACTION}" == init ]] && exit 0
[[ "${ACTION}" == plan ]] && { "${TF[@]}" plan -input=false; exit; }
if [[ "${ACTION}" == destroy ]]; then
  "${TF[@]}" plan -destroy -out=destroy.tfplan
  "${TF[@]}" apply -input=false destroy.tfplan
  exit
fi
if [[ "${ACTION}" == deploy ]]; then
  "${TF[@]}" plan -out=deploy.tfplan
  "${TF[@]}" apply -input=false deploy.tfplan
fi
RG="$("${TF[@]}" output -raw resource_group_name)"
CLUSTER="$("${TF[@]}" output -raw cluster_name)"
case "${ACTION}" in
  sleep) az aks stop --resource-group "${RG}" --name "${CLUSTER}"; exit ;;
  wake) az aks start --resource-group "${RG}" --name "${CLUSTER}"; exit ;;
esac
az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing

verify() {
  kubectl -n serving rollout status deployment/model-api --timeout=180s
  local address=""
  for _ in $(seq 1 60); do
    address="$(kubectl -n serving get svc model-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
    [[ -n "${address}" ]] && break
    sleep 5
  done
  [[ -n "${address}" ]] || { echo 'Azure LoadBalancer has no address' >&2; exit 1; }
  curl --fail --silent --show-error --retry 12 --retry-all-errors --retry-delay 5 "http://${address}:8080/readyz"
  curl --fail --silent --show-error "http://${address}:8080/model-info"
  curl --fail --silent --show-error -H 'Content-Type: application/json' \
    -d '{"customer_ids":[7]}' "http://${address}:8080/predict"
  echo "Model API: http://${address}:8080"
  [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "Model API: http://${address}:8080" >> "${GITHUB_STEP_SUMMARY}"
}
[[ "${ACTION}" == verify ]] && { verify; exit; }
if [[ "${ACTION}" == release ]]; then
  export VERSION
  manifest="$(mktemp)"
  trap 'rm -f "${manifest}"' EXIT
  kubectl -n data get configmap retrain-job-template -o json | python3 -c '
import json, os, sys
pod = json.loads(json.load(sys.stdin)["data"]["pod-spec.json"])
c = pod["containers"][0]
c["env"].append({"name":"VERSION", "value": os.environ["VERSION"]})
c["args"][0] = c["args"][0].replace("python -m retrain.main", "bash scripts/model_release_local.sh \"$VERSION\" \"$IMAGE_TAG\"")
print(json.dumps({"apiVersion":"batch/v1", "kind":"Job", "metadata":{"name":"model-release", "namespace":"data"}, "spec":{"backoffLimit":0,"ttlSecondsAfterFinished":3600,"template":{"spec":pod}}}))
' > "${manifest}"
  bash ops/scripts/run_job.sh "${manifest}" data
  exit
fi

ACR="$("${TF[@]}" output -raw acr_login_server)"
TAG="${TAG:-$(git rev-parse HEAD)}"
az acr login --name "${ACR%%.*}"
for service in training model-api mlflow remediator drift-monitor retrain; do
  docker build --file infra/docker/Dockerfile --target "${service}" --tag "${ACR}/mlp-${service}:${TAG}" .
  docker push "${ACR}/mlp-${service}:${TAG}"
done
for namespace in data serving staging observability; do
  kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f -
done
if ! kubectl -n data get secret postgres-auth >/dev/null 2>&1; then
  kubectl -n data create secret generic postgres-auth --from-literal=username=mlp --from-literal=postgres-password="$(openssl rand -hex 16)"
fi
if ! kubectl -n data get secret minio-auth >/dev/null 2>&1; then
  kubectl -n data create secret generic minio-auth --from-literal=root-user=minioadmin --from-literal=root-password="$(openssl rand -hex 16)"
fi
if ! kubectl -n observability get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n observability create secret generic grafana-admin --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -hex 16)"
fi
helm_apply() {
  local release="$1" namespace="$2" chart="$3"; shift 3
  helm upgrade --install "${release}" "${chart}" -n "${namespace}" --atomic --wait --timeout 15m "$@"
}
helm_apply kube-prometheus-stack observability infra/charts/kube-prometheus-stack-91.8.2.tgz -f infra/deploy/charts/observability/values-prometheus.yaml
helm_apply loki observability infra/charts/loki-7.3.0.tgz -f infra/deploy/charts/observability/values-loki.yaml
helm_apply alloy observability infra/charts/alloy-1.13.0.tgz -f infra/deploy/charts/observability/values-alloy.yaml
helm_apply observability-content observability infra/deploy/charts/observability
for service in postgres minio; do
  helm_apply "${service}" data "infra/deploy/charts/${service}" --set auth.createSecret=false --set "auth.existingSecret=${service}-auth"
done
helm_apply redis data infra/deploy/charts/redis
helm_apply mlflow data infra/deploy/charts/mlflow --set "image.repository=${ACR}/mlp-mlflow,image.tag=${TAG}"

# Port-forwards exist only on the ephemeral Actions runner, never on the laptop.
PF_PIDS=()
cleanup() { for pid in "${PF_PIDS[@]}"; do kill "${pid}" 2>/dev/null || true; done; }
trap cleanup EXIT
kubectl -n data port-forward svc/minio 9000:9000 >/tmp/mlp-minio-forward.log 2>&1 & PF_PIDS+=("$!")
kubectl -n data port-forward svc/mlflow 5000:5000 >/tmp/mlp-mlflow-forward.log 2>&1 & PF_PIDS+=("$!")
curl --fail --silent --retry 30 --retry-all-errors --retry-delay 2 http://localhost:9000/minio/health/ready
curl --fail --silent --retry 30 --retry-all-errors --retry-delay 2 http://localhost:5000/health
# Do not overwrite existing drifted features or train extra versions on reruns.
CHAMPION="$(curl --fail --silent 'http://localhost:5000/api/2.0/mlflow/registered-models/search' | python3 -c '
import json,sys
models=json.load(sys.stdin).get("registered_models",[])
print(next((a["version"] for m in models if m["name"]=="loan-default" for a in m.get("aliases",[]) if a["alias"]=="champion"),""))')"
export TRAINING_IMAGE="${ACR}/mlp-training:${TAG}"
if [[ -z "${CHAMPION}" ]]; then
  make seed-data publish-feast-data
  for job in apply-job.yaml materialize-job.yaml verify-job.yaml; do
    sed "s|localhost:5001/training:dev|${TRAINING_IMAGE}|g" "infra/deploy/feast/${job}" > /tmp/mlp-feast-job.yaml
    bash ops/scripts/run_job.sh /tmp/mlp-feast-job.yaml data
  done
  bash ops/scripts/train_mlflow.sh
  CHAMPION="$(curl --fail --silent 'http://localhost:5000/api/2.0/mlflow/registered-models/alias?name=loan-default&alias=champion' | python3 -c 'import json,sys; print(json.load(sys.stdin)["model_version"]["version"])')"
fi
SKIP_SMOKE=1 DEPLOY_TARGET=azure MODEL_API_REPOSITORY="${ACR}/mlp-model-api" \
  bash ops/scripts/deploy.sh model-api serving "${TAG}" --set "model.version=${CHAMPION}"
helm_apply remediator observability infra/deploy/charts/remediator --set "image.repository=${ACR}/mlp-remediator,image.tag=${TAG}"
PG_USER="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.username}' | base64 -d)"
PG_PASS="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.postgres-password}' | base64 -d)"
kubectl -n observability create secret generic drift-monitor-db \
  --from-literal=database-url="postgresql+psycopg://${PG_USER}:${PG_PASS}@postgres.data.svc:5432/mlp" --dry-run=client -o yaml | kubectl apply -f -
helm_apply retrain data infra/deploy/charts/retrain --set "image.repository=${ACR}/mlp-retrain,image.tag=${TAG}" \
  --set "env.MODEL_API_REPOSITORY=${ACR}/mlp-model-api,env.TRAINING_IMAGE=${TRAINING_IMAGE},env.IMAGE_TAG=${TAG},env.DEPLOY_TARGET=azure"
helm_apply drift-monitor observability infra/deploy/charts/drift-monitor --set "image.repository=${ACR}/mlp-drift-monitor,image.tag=${TAG}"
verify
