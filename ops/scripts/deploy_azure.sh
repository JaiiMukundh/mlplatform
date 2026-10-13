#!/usr/bin/env bash
# Deploy the MLPlatform serving path to Azure AKS (Terraform + ACR + Helm).
# [HUMAN] ONLY — creates billable resources. See ops/docs/azure-port.md.
# Prerequisites: az login, Terraform, Docker, kubectl, Helm.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

TAG="${TAG:-dev}"
TF="terraform -chdir=infra/envs/azure"

echo "========================================================================"
echo ">> Step 1: Provisioning Azure infrastructure via Terraform..."
echo "========================================================================"
${TF} apply -auto-approve

RG="$(${TF} output -raw resource_group_name)"
CLUSTER="$(${TF} output -raw cluster_name)"
ACR_LOGIN="$(${TF} output -raw acr_login_server)"
ACR_NAME="${ACR_LOGIN%%.*}"
DB_FQDN="$(${TF} output -raw db_fqdn)"
DB_USER="$(${TF} output -raw db_username)"
DB_PASS="$(${TF} output -raw db_password)"
MODEL_API_CLIENT_ID="$(${TF} output -json workload_client_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["model-api"])')"

echo "========================================================================"
echo ">> Step 2: Connecting kubectl + Docker to AKS/ACR..."
echo "========================================================================"
az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
az acr login --name "${ACR_NAME}"

echo "========================================================================"
echo ">> Step 3: Building and pushing model-api:${TAG} to ACR..."
echo "========================================================================"
hadolint infra/docker/model_api.Dockerfile
docker build --file infra/docker/model_api.Dockerfile \
  --tag "${ACR_LOGIN}/mlp-model-api:${TAG}" .
docker push "${ACR_LOGIN}/mlp-model-api:${TAG}"

echo "========================================================================"
echo ">> Step 4: Seeding the Flexible Server credentials secret..."
echo "========================================================================"
kubectl create namespace serving --dry-run=client -o yaml | kubectl apply -f -
kubectl -n serving create secret generic azure-postgres-app \
  --from-literal=database-url="postgresql+psycopg://${DB_USER}:${DB_PASS}@${DB_FQDN}:5432/mlp?sslmode=require" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "========================================================================"
echo ">> Step 5: Deploying model-api to AKS..."
echo "========================================================================"
helm upgrade --install model-api infra/deploy/charts/model-api \
  -f infra/deploy/charts/model-api/values.yaml \
  -f infra/deploy/charts/model-api/values-azure.yaml \
  --set "image.repository=${ACR_LOGIN}/mlp-model-api" \
  --set "image.tag=${TAG}" \
  --set 'serviceAccount.annotations.azure\.workload\.identity/client-id'="${MODEL_API_CLIENT_ID}" \
  --namespace serving --create-namespace \
  --atomic --wait --timeout 10m

echo "========================================================================"
echo ">> Step 6: Verifying the Azure LoadBalancer endpoint..."
echo "========================================================================"
for _ in $(seq 1 30); do
  LB_IP="$(kubectl -n serving get svc model-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "${LB_IP}" ] && break
  sleep 10
done
echo "LoadBalancer IP: ${LB_IP:-<pending>}"
curl -s "http://${LB_IP}:8080/healthz" || echo "Pending initialization..."

echo "========================================================================"
echo ">> AKS serving deployment complete. Tear down with: bash ops/scripts/destroy_azure.sh"
echo "========================================================================"
