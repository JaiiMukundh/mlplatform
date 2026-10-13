#!/usr/bin/env bash
# Deploy the FULL cloud-native platform to Azure AKS, including training.
# [HUMAN] ONLY — creates billable resources. Read ops/docs/azure-port.md first.
# Prerequisites: az login, Terraform, Docker, kubectl, Helm, uv.
# Usage: TAG=v1.0.0 bash ops/scripts/deploy_azure_full.sh
#
# What it does (idempotent, safe to rerun):
#  1. terraform apply (RG, VNet, ACR, AKS 2x2vCPU=4 vCPU cap, Blob, Flexible DB)
#  2. Build + push all 6 images to ACR (model-api, training, mlflow,
#     remediator, drift-monitor, retrain)
#  3. Data layer on AKS via the SAME charts as Kind (postgres/minio/redis/
#     mlflow + values-azure image overlays) — training Jobs need zero changes
#  4. Seed data -> publish to in-cluster MinIO -> Feast apply/materialize/verify
#  5. Train champion v1 + candidate v2 on AKS (train_azure.sh)
#  6. Deploy model-api (pinned to latest version), retrain + drift-monitor
# Tear down: sleep (azure_compute.sh sleep, state kept) or full destroy.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

TAG="${TAG:-v1.0.0}"
TF="terraform -chdir=infra/envs/azure"

echo "========================================================================"
echo ">> Step 1: Provisioning Azure infrastructure via Terraform..."
echo "========================================================================"
${TF} apply -auto-approve

RG="$(${TF} output -raw resource_group_name)"
CLUSTER="$(${TF} output -raw cluster_name)"
ACR_LOGIN="$(${TF} output -raw acr_login_server)"
ACR_NAME="${ACR_LOGIN%%.*}"

echo "========================================================================"
echo ">> Step 2: Connecting kubectl + Docker to AKS/ACR..."
echo "========================================================================"
az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
az acr login --name "${ACR_NAME}"

echo "========================================================================"
echo ">> Step 3: Building and pushing images to ${ACR_LOGIN} (tag ${TAG})..."
echo "========================================================================"
build_push() {
  local dockerfile="$1" repo="$2"
  docker build --file "${dockerfile}" --tag "${ACR_LOGIN}/${repo}:${TAG}" .
  docker push "${ACR_LOGIN}/${repo}:${TAG}"
}
build_push infra/docker/model_api.Dockerfile mlp-model-api
build_push infra/docker/training.Dockerfile mlp-training
build_push infra/docker/mlflow.Dockerfile mlp-mlflow
build_push infra/docker/remediator.Dockerfile mlp-remediator
build_push infra/docker/drift_monitor.Dockerfile mlp-drift-monitor
build_push infra/docker/retrain.Dockerfile mlp-retrain

echo "========================================================================"
echo ">> Step 4: Namespaces + data-layer secrets (created once, reused)..."
echo "========================================================================"
for ns in data serving staging observability; do
  kubectl create namespace "${ns}" --dry-run=client -o yaml | kubectl apply -f -
done
if ! kubectl -n data get secret postgres-auth >/dev/null 2>&1; then
  kubectl -n data create secret generic postgres-auth \
    --from-literal=username=mlp \
    --from-literal=postgres-password="$(openssl rand -hex 16)"
fi
if ! kubectl -n data get secret minio-auth >/dev/null 2>&1; then
  kubectl -n data create secret generic minio-auth \
    --from-literal=root-user=minioadmin \
    --from-literal=root-password="$(openssl rand -hex 12)"
fi

echo "========================================================================"
echo ">> Step 5: Data layer on AKS (postgres/minio/redis/mlflow)..."
echo "========================================================================"
helm upgrade --install postgres infra/deploy/charts/postgres \
  --namespace data --set auth.createSecret=false --set auth.existingSecret=postgres-auth \
  --atomic --wait --timeout 10m
helm upgrade --install minio infra/deploy/charts/minio \
  --namespace data --set auth.createSecret=false --set auth.existingSecret=minio-auth \
  --atomic --wait --timeout 10m
helm upgrade --install redis infra/deploy/charts/redis \
  --namespace data --atomic --wait --timeout 10m
helm upgrade --install mlflow infra/deploy/charts/mlflow \
  -f infra/deploy/charts/mlflow/values.yaml \
  -f infra/deploy/charts/mlflow/values-azure.yaml \
  --set "image.repository=${ACR_LOGIN}/mlp-mlflow" --set "image.tag=${TAG}" \
  --set image.pullPolicy=Always \
  --namespace data --atomic --wait --timeout 10m

echo "========================================================================"
echo ">> Step 6: Seed data + Feast on AKS..."
echo "========================================================================"
uv run python -m ml.data.generate --out data --seed 42
kubectl -n data port-forward svc/minio 9000:9000 >/tmp/pf-minio-azure.log 2>&1 &
PF_MINIO=$!
trap 'kill ${PF_MINIO} 2>/dev/null || true' EXIT
sleep 5
bash ops/scripts/publish_feast_data.sh
render_feast_job() {
  sed -e "s|localhost:5001/training:dev|${ACR_LOGIN}/mlp-training:${TAG}|g" \
    "infra/deploy/feast/$1" >"/tmp/feast-azure-$1"
  bash ops/scripts/run_job.sh "/tmp/feast-azure-$1" data
}
render_feast_job apply-job.yaml
render_feast_job materialize-job.yaml
render_feast_job verify-job.yaml
kill "${PF_MINIO}" 2>/dev/null || true
trap - EXIT

echo "========================================================================"
echo ">> Step 7: Train champion v1 + candidate v2 ON AKS..."
echo "========================================================================"
TRIGGER=manual TAG="${TAG}" bash ops/scripts/train_azure.sh
TRIGGER=manual TAG="${TAG}" bash ops/scripts/train_azure.sh

echo "========================================================================"
echo ">> Step 8: Deploy model-api + retrain + drift-monitor on AKS..."
echo "========================================================================"
kubectl -n data port-forward svc/mlflow 5000:5000 >/tmp/pf-mlflow-azure.log 2>&1 &
PF_MLFLOW=$!
sleep 5
LATEST="$(curl -s "http://localhost:5000/api/2.0/mlflow/model-versions/search?filter=name%3D%27loan-default%27" |
  python3 -c "import json,sys; print(max(int(v['version']) for v in json.load(sys.stdin).get('model_versions',[])))")"
kill "${PF_MLFLOW}" 2>/dev/null || true
echo "latest model version: ${LATEST}"
MODEL_API_CLIENT_ID="$(${TF} output -json workload_client_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["model-api"])')"
helm upgrade --install model-api infra/deploy/charts/model-api \
  -f infra/deploy/charts/model-api/values.yaml \
  -f infra/deploy/charts/model-api/values-azure.yaml \
  --set "image.repository=${ACR_LOGIN}/mlp-model-api" --set "image.tag=${TAG}" \
  --set image.pullPolicy=Always \
  --set "model.version=${LATEST}" \
  --set 'serviceAccount.annotations.azure\.workload\.identity/client-id'="${MODEL_API_CLIENT_ID}" \
  --namespace serving --atomic --wait --timeout 10m

helm upgrade --install remediator infra/deploy/charts/remediator \
  --set "image.repository=${ACR_LOGIN}/mlp-remediator" --set "image.tag=${TAG}" \
  --set image.pullPolicy=Always \
  --namespace observability --create-namespace --atomic --wait --timeout 5m

PG_USER="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.username}' | base64 -d)"
PG_PASS="$(kubectl -n data get secret postgres-auth -o jsonpath='{.data.postgres-password}' | base64 -d)"
kubectl -n observability create secret generic drift-monitor-db \
  --from-literal=database-url="postgresql+psycopg://${PG_USER}:${PG_PASS}@postgres.data.svc:5432/mlp" \
  --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install retrain infra/deploy/charts/retrain \
  -f infra/deploy/charts/retrain/values.yaml \
  -f infra/deploy/charts/retrain/values-azure.yaml \
  --set "image.repository=${ACR_LOGIN}/mlp-retrain" --set "image.tag=${TAG}" \
  --namespace data --atomic --wait --timeout 5m
helm upgrade --install drift-monitor infra/deploy/charts/drift-monitor \
  -f infra/deploy/charts/drift-monitor/values.yaml \
  -f infra/deploy/charts/drift-monitor/values-azure.yaml \
  --set "image.repository=${ACR_LOGIN}/mlp-drift-monitor" --set "image.tag=${TAG}" \
  --namespace observability --atomic --wait --timeout 5m
kubectl -n observability rollout restart deployment/drift-monitor
kubectl -n observability rollout status deploy/drift-monitor --timeout=180s

echo "========================================================================"
echo ">> Step 9: Verifying the Azure LoadBalancer endpoint..."
echo "========================================================================"
for _ in $(seq 1 30); do
  LB_IP="$(kubectl -n serving get svc model-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "${LB_IP}" ] && break
  sleep 10
done
echo "LoadBalancer IP: ${LB_IP:-<pending>}"
curl -s "http://${LB_IP}:8080/healthz" || echo "Pending initialization..."

echo "========================================================================"
echo ">> AKS full-platform deployment complete (training runs on AKS)."
echo ">> Sleep (keep state): bash ops/scripts/azure_compute.sh sleep"
echo ">> Tear down all:      bash ops/scripts/destroy_azure.sh"
echo "========================================================================"
