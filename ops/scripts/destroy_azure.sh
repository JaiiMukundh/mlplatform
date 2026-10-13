#!/usr/bin/env bash
# Tear down the Azure Cloud Infrastructure to eliminate credit burn.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

echo "========================================================================"
echo ">> Destroying Azure Infrastructure via Terraform..."
echo "========================================================================"
terraform -chdir=infra/envs/azure destroy -auto-approve

echo ">> Azure Infrastructure destroyed successfully. Billing stopped."
