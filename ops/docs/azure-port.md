# Azure Deployment Runbook & Cloud Port Guide

This document provides the complete checklist for deploying the ML Platform to **Microsoft Azure** on **AKS** — a straight port of the old AWS design (EKS→AKS, VPC→VNet, S3→Blob Storage, RDS→PostgreSQL Flexible Server, ECR→ACR, IRSA→Workload Identity) using **pure HashiCorp Terraform** (`azurerm`). All cloud spend comes from the Azure for Students grant ($0.00 personal spend).

> [!WARNING]
> **Cost & Safety Guardrail:** Running on Azure incurs billable charges. The agent is strictly forbidden from running `terraform apply` against Azure (AGENTS.md Rule 12). Applying is **[HUMAN]** (`make azure-apply` refuses and points at `bash ops/scripts/deploy_azure.sh`). Keep the environment up ONLY for the demo window, then tear it down.

---

## 1. Architecture & Cost Matrix

### Cloud Architecture Overview
Defined in `infra/envs/azure` (composition) + `infra/modules/*_azure`:

- **Compute:** AKS (`cluster_aks`: OIDC + workload identity on, 2× `Standard_B2s` nodes) in a dedicated `aks-subnet`.
- **Networking:** VNet `10.0.0.0/16` (`network_azure`) split into `aks`/`db`/`public` subnets + NSG (model-api 8080, Grafana 3000, MLflow 5000, MinIO 9001, Ops UI 8050).
- **Registry:** ACR Basic (`image_registry_azure`); AKS kubelet gets `AcrPull` — no imagePullSecrets.
- **Database:** PostgreSQL Flexible Server `B_Standard_B1ms` (`database_azure`) in the delegated `db-subnet` with private DNS; `mlp` database; generated admin password (Terraform `random_password`, never in git).
- **Object storage (S3 equivalent):** Blob Storage account (`object_storage_azure`, LRS, versioned) with `mlflow-artifacts`, `feast-offline`, `ml-data` containers. MinIO stays in-cluster on AKS for the Feast offline store (Feast has no native Blob backend — zero app changes); MLflow artifacts move to Blob as a follow-up (needs the Azure artifact extras in the mlflow image).
- **Identity (IRSA equivalent):** three user-assigned managed identities (`iam_azure`) with federated credentials on the AKS OIDC issuer — `model-api` gets Blob Reader, `retrain`/`mlflow` get Blob Contributor. Pods authenticate with zero static keys.
- **Guardrail:** monthly consumption budget ($50 default) + email action group; P9.6 tears everything down.

### Resource Cost Matrix (estimate, `indiasouthcentral`)
| Component | Azure Resource | ~Hourly |
|---|---|---|
| **Kubernetes** | AKS (free tier control plane) + 2× `Standard_B2s` nodes | ~\$0.08 |
| **Database** | PostgreSQL Flexible `B_Standard_B1ms` + 32 GB P4 | ~\$0.03 |
| **Registry** | ACR Basic | ~\$0.006 |
| **Storage** | Blob LRS + versions | < \$0.01 |
| **Networking** | VNet/NSG free; LoadBalancer (model-api) | ~\$0.025 |
| **Total** | | **~ \$0.15 / hr (~\$0.45 per 3-hour demo)** |

---

## 2. Infrastructure as Code (Terraform)

- `infra/envs/azure/main.tf`: provider, Resource Group, `network` → `registry` → `cluster` (with `acr_id`) → `storage` → `db` → `api_access` modules, plus budget + action group.
- `variables.tf` / `outputs.tf`: cluster name, ACR login server, Blob endpoint, DB FQDN, workload client IDs.

```bash
make azure-init       # init, no creds needed
make azure-validate   # syntax/schema check
make azure-plan       # dry-run (needs az login; billable: nothing)
# [HUMAN] apply:
bash ops/scripts/deploy_azure.sh
```

---

## 3. Step-by-Step Deployment Runbook ([HUMAN])

### Step 1: Authenticate
```bash
az login
# .edu / Students: verify with your school email (one subscription per
# person), then use YOUR id (az account show --query id -o tsv), also set in
# infra/envs/azure/terraform.tfvars (gitignored).
az account set --subscription "<your-subscription-id>"
```

### Step 2: Apply + deploy serving (`TAG=v1.0.0` recommended)
```bash
TAG=v1.0.0 bash ops/scripts/deploy_azure.sh
```
The script: `terraform apply` → `az aks get-credentials` → `az acr login` → build/push `mlp-model-api:${TAG}` → seed `azure-postgres-app` secret (Flexible Server URL from outputs) → `helm upgrade --install model-api` with `values.yaml` + `values-azure.yaml` (ACR repo, LoadBalancer, workload-identity SA) → smoke `http://<LB-IP>:8080/healthz`.

### Step 3: Verify
```bash
curl http://<LB-IP>:8080/healthz
curl -X POST http://<LB-IP>:8080/predict -H "Content-Type: application/json" \
  -d '{"customer_ids": [1001, 1002, 1003]}'
```

---

## 4. Credit Preservation & Teardown (serving-only path)

- **Pause billing now:** `bash ops/scripts/destroy_azure.sh` (full `terraform destroy` — billing to zero). There is no VM-deallocate equivalent for AKS; the node pool bills while it exists.
- Keep the demo window tight; the budget alarm mails at 80% (forecasted) and 100% (actual) of $50.

---

## 5. Student/Edu Account Restrictions (researched 2026-10-13)

Sources: Microsoft Learn (vCPU quotas, subscription limits, AKS VM sizes) +
current student-subscription Q&A. The agent cannot see your quota; run
`make azure-preflight` (read-only, spends nothing) — it fails fast with the
fix for each case. Key facts:

| Restriction | What it means for this project |
|---|---|
| **$100 credit / 12 months, no quota increases** | Support cannot raise any limit. If a SKU/region is blocked, switch SKU or region — never wait on a ticket. |
| **Total Regional vCPUs often capped at ~4** | AKS default (2 nodes × 2 vCPU) = exactly 4. `node_count` is validated to 1–2; `vm_size` to 2-vCPU burstable SKUs. |
| **B-series v1 (B1s/B2s) retiring per region** | `Standard_B2s` may show `NotAvailableForSubscription`. Fallback: `Standard_B2as_v2` (2 vCPU / 8 GB, burstable, AMD) via `-var vm_size=...` or `AZURE_VM_SIZE`. |
| **1 GB SKUs (B2ats_v2/B2pts_v2) CANNOT run AKS** | Kubelet fails with 0 allocatable memory. Excluded by terraform validation. The "750 free hours" marketing does not apply to Kubernetes nodes. |
| **Allowed deployment regions restricted per subscription** | The `Allowed resource deployment regions` policy differs per student. Default `indiasouthcentral` may be blocked — override with `-var location=...` after checking portal Policy. AKS + Flexible Server must both exist in the chosen region. |
| **Max 3 AKS clusters per subscription per region** | We deploy 1. No conflict unless you experiment in parallel. |
| **No GPUs, no D-series headroom, no premium networking** | Irrelevant here: sklearn trains on CPU in minutes; LB is Standard (free-ish ~$0.025/hr). |
| **PostgreSQL Flexible B1ms + Blob LRS + ACR Basic** | All permitted on student offers; this is why the Terraform stack uses exactly these tiers. |

Preflight covers: `az login`, provider registrations, SKU `restrictions[]`
for your size/region, and Total Regional vCPU limit vs need.

> Live snapshot for this subscription (2026-10-13, `indiasouthcentral`):
> `cores` 4/6 used, `standardBSFamily` 4/4 **full**, `standardBasv2Family`
> 0/10 free — all held by the deallocated leftover `mlp-cloud-vm`
> (Standard_B4ms). Both `Standard_B2s` and `Standard_B2as_v2` show **no**
> SKU restrictions here. Until the leftover VM is deleted, the default
> 2×B2s fails preflight; `AZURE_VM_SIZE=Standard_B2as_v2 AZURE_NODE_COUNT=1`
> passes. After deleting it, 2×B2s or 2×B2as_v2 both fit (B2as_v2 preferred:
> 8 GB RAM gives training headroom).

---

## 6. Full Platform on AKS (training runs on the cloud)

The serving-only path (Section 3) is the grade-parity shortcut. The full path
runs **everything** on AKS with the same charts/Jobs as Kind — only the image
registry changes (`localhost:5001` → ACR):

```bash
make azure-preflight
# [HUMAN]:
TAG=v1.0.0 bash ops/scripts/deploy_azure_full.sh
```

The script provisions infra → pushes all 6 images to ACR → installs the data
layer (postgres/minio/redis/mlflow + `values-azure.yaml` image overlays) →
seeds data → Feast jobs (image retagged to ACR) → **trains champion v1 +
candidate v2 in AKS Jobs** (`infra/deploy/training/train-job-azure.yaml`,
sized for 2-vCPU nodes: 500m/1Gi req, 1900m/3Gi lim) → deploys model-api
(pinned to latest version), remediator, retrain + drift-monitor.

Manual retrain later (needs AKS kubectl context):

```bash
TAG=v1.0.0 TRIGGER=manual bash ops/scripts/train_azure.sh
```

Drift-triggered retraining works as locally: drift-monitor spawns retrain Jobs
on AKS nodes, talking to `*.data.svc` ClusterIP names identical to Kind.

---

## 7. Kill-Switch: Stop Paying, Keep the State

| Action | Command ([HUMAN]) | Compute cost after | What stays | Resume |
|---|---|---|---|---|
| **Sleep** (recommended) | `bash ops/scripts/azure_compute.sh sleep` | ~$0/hr (VMs deallocated) | Everything: AKS object, PVCs (postgres/minio/redis data, MLflow artifacts), ACR, Blob, Flexible DB, registry versions/aliases | `bash ops/scripts/azure_compute.sh wake` → pods reschedule onto existing disks, serving resumes in minutes |
| **Destroy compute** | `terraform destroy -target=module.cluster` (review plan first) | $0 compute | ACR images, Blob containers, Flexible DB, VNet, identities. **Lost:** in-cluster postgres (MLflow lineage), MinIO artifacts, Redis. Rehydrate via full deploy (registry re-trains deterministically) | `deploy_azure_full.sh` again |
| **Destroy all** | `bash ops/scripts/destroy_azure.sh` | $0 total | Nothing (credit preserved) | Full rebuild from scratch |

While asleep you still pay pennies for disks (~4× small PVCs), Blob, and the
Flexible Server (~$0.03/hr) — that is the price of "registry and all can stay".
Tear down fully before the credit window ends.
