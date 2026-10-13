#!/usr/bin/env bash
# Sleep/wake the AKS cluster to stop/start VM billing without losing state.
# [HUMAN] ONLY — needs az login; the cluster must already exist.
# Usage: bash ops/scripts/azure_compute.sh [sleep|wake]
#   sleep: az aks stop  (nodes deallocated: ~$0/hr compute; disks + managed
#          services keep their small charges; registry/data fully preserved)
#   wake:  az aks start (nodes return; workloads reschedule onto old PVCs)
# Full teardown instead: bash ops/scripts/destroy_azure.sh (billing to zero,
# in-cluster state lost; Blob/Flexible/ACR persist).
set -Eeuo pipefail

MODE="${1:?usage: bash ops/scripts/azure_compute.sh [sleep|wake]}"
TF="terraform -chdir=infra/envs/azure"

RG="$(${TF} output -raw resource_group_name)"
CLUSTER="$(${TF} output -raw cluster_name)"

case "${MODE}" in
  sleep)
    echo "stopping AKS ${CLUSTER} (compute billing -> ~0, state preserved)..."
    az aks stop --resource-group "${RG}" --name "${CLUSTER}"
    echo "asleep. Resume with: bash ops/scripts/azure_compute.sh wake"
    ;;
  wake)
    echo "starting AKS ${CLUSTER}..."
    az aks start --resource-group "${RG}" --name "${CLUSTER}"
    az aks get-credentials --resource-group "${RG}" --name "${CLUSTER}" --overwrite-existing
    echo "awake. Verify with: kubectl get pods -A"
    ;;
  *)
    echo "usage: bash ops/scripts/azure_compute.sh [sleep|wake]" >&2
    exit 2
    ;;
esac
