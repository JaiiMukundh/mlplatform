# Azure Cloud Architecture (LOCKED 2026-10-13)

This is the single source of truth for the **whole cloud setup**: account,
network, cluster, data, workloads, identity, outer CI/CD loop, kill-switch,
and cost. Status: designed + scaffolded, **not yet applied** (apply is
[HUMAN], P9.6). Changes to anything below go through `ops/docs/DECISIONS.md`
per AGENTS.md. Companion runbook: `ops/docs/azure-port.md`.

---

## 1. Account & hard limits (Azure for Students, self-serve)

- Subscription: personal **Azure for Students** (`Azure for Students`,
  Enabled), verified via school email. Individual offer — school IT has no
  control over it. One subscription per person, $100 credit / 12 months.
- Region: `indiasouthcentral` (default; override `-var location=` if your
  subscription's allowed-regions policy blocks it).
- Quotas that shape everything (measured live, cannot be raised on Students):
  `cores` 6 max, B-family 4 max, Basv2-family 10 max, 3 AKS clusters max.
  Gate: `make azure-preflight` (read-only) fails fast with the fix.
- Node policy: 2 nodes × 2 vCPU = 4 vCPU, exactly the cap. Terraform
  validates `node_count` 1–2 and bans 1 GB SKUs (B2ats_v2/B2pts_v2 break AKS
  kubelets). Default `Standard_B2s`; fallback `Standard_B2as_v2` (2 vCPU /
  8 GB) if B-series v1 is retired in your region.

## 2. Managed Azure layer (all in `infra/envs/azure`, one resource group)

| Resource | Module | Shape |
|---|---|---|
| Resource group | — | `mlp-dev-rg` |
| VNet + subnets | `network_azure` | `10.0.0.0/16` → `aks-subnet` (.1), `db-subnet` (.2, delegated to Flexible Server + Storage endpoint), `public-subnet` (.3) |
| NSG (on aks-subnet) | `network_azure` | Allow 8080 (model-api), 3000 (grafana), 5000 (mlflow), 9001 (minio), 8050 (ops UI) — broad source `*`; hardening follow-up, real entry is via LoadBalancer + port-forwards (§8) |
| AKS | `cluster_aks` | K8s 1.30, free tier, OIDC + workload identity on, kubenet + Standard LB, single `default` pool (2 × B2s, 30 GB OS disk), kubelet has AcrPull |
| ACR | `image_registry_azure` | Basic tier; holds 6 images (`mlp-model-api/training/mlflow/remediator/drift-monitor/retrain`) |
| Blob | `object_storage_azure` | LRS, versioned; containers `mlflow-artifacts`, `feast-offline`, `ml-data` (reserved for cutover; live path still uses in-cluster MinIO — honest seam, §9) |
| PostgreSQL Flexible | `database_azure` | `B_Standard_B1ms`, 32 GB P4, private DNS in db-subnet, `mlp` database, Terraform-generated password (never in git) |
| Identities | `iam_azure` | 3 user-assigned IDs (model-api: Blob Reader; retrain/mlflow: Blob Contributor) with federated credentials. **Live today only for model-api**; retrain/mlflow subjects are provisioned for the Blob cutover (§9) |
| Budget | — | $50/month consumption budget + email alerts |

Deliberately absent: GPUs, D-series, App Gateway, Azure Monitor/Container Insights (we run our own Prometheus stack), managed Redis (in-cluster, rematerializable).

## 3. AKS node-fit math (requests = what schedules)

Approx steady-state CPU requests vs ~3.8 CPU allocatable on 2 nodes:

- kube-system ~0.5 · data (postgres/redis/minio/mlflow) 0.45 · serving
  (model-api ×2) 0.2 · observability (prometheus/operator/grafana/loki/
  alloy/exporters) ~0.75 · drift-monitor 0.2 + remediator 0.05 ≈ **~2.2 CPU**,
  ~60% of capacity. Training/retrain Jobs add 0.5 each when running; HPA can
  add 0.4 more at full burst. Fits on B2s with headroom; B2as_v2 removes all
  memory pressure (B2s nodes have ~2.5–3 GB usable RAM each).

## 4. In-cluster platform (same charts as Kind, ACR images)

| Namespace | Workloads | Image | Talks to |
|---|---|---|---|
| `data` | postgres, minio, redis, mlflow, feast Jobs, train Jobs, retrain Jobs, gate Jobs | ACR (`mlp-*`) | each other via `*.data.svc` ClusterIP — identical DNS to Kind, zero app changes |
| `serving` | model-api (2–6 replicas, HPA 60% CPU) + model-api-staging (release flow) | ACR `mlp-model-api` | `mlflow.data.svc:5000` (artifact pull), `redis.data.svc` (features), `postgres.data.svc` (prediction_log), Azure LB (port 8080) |
| `staging` | model-api-staging during releases | ACR | same as serving, NodePort 30081 (in-cluster only) |
| `observability` | kube-prometheus-stack, loki, alloy, drift-monitor, remediator | ACR / pinned upstream | scrapes all namespaces; Alertmanager → remediator webhook; drift-monitor → `postgres.data.svc` + spawns Jobs in `data` |

Postgres hosts three databases (app `mlp`, `mlflow` backend, `feast` registry);
MinIO holds `feast-offline` + `mlflow-artifacts` buckets; Redis is the Feast
online store (ephemeral, rematerializable from MinIO).

## 5. The four flows on AKS

1. **Serve:** LB:8080 → `POST /predict` → Redis hydrate (<2 ms) → pinned
   model → async PG log → probability. Staging + prod + LB verified by
   `deploy_azure_full.sh` step 9.
2. **Train (cloud):** `train_azure.sh` renders `train-job-azure.yaml`
   (ACR image, B2s-safe resources) → AKS Job → Feast point-in-time join from
   MinIO → sklearn fit → registers version in MLflow (`champion` first,
   `candidate` after).
3. **Self-heal (cloud, autonomous):** drift-monitor (10 s loop, PSI>0.25 ×2
   features ×2 cycles + cooldown) → retrain Job on AKS → candidate → gate →
   staging loadcheck → promote champion → rolling update. No GitHub involved
   (`TRIGGER_MODE=local`).
4. **Observe:** Prometheus/Alertmanager/Grafana/Loki, same dashboards as
   local; remediator scales HPA floors on latency alerts.

## 6. Outer loop — CI/CD (LOCKED decisions 2026-10-13)

- **CI** (`ci.yml`, GitHub-hosted): unchanged. Never touches Azure.
- **CD-Azure**: NEW workflow (not yet written): `workflow_dispatch` only,
  environment reviewer = human, GitHub-hosted runner, **OIDC federated auth**
  (no stored secrets), reuses `deploy_azure_full.sh` verbatim. Never auto on
  push. Never destroy.
- **Model-release on Azure**: stays in-cluster (flow 3). `model-release.yml`
  remains laptop-scoped unless `TRIGGER_MODE=github` is ever adopted.
- **Secrets**: subscription/client IDs as plain vars; DB passwords
  Terraform-generated; `terraform.tfvars` gitignored; kubeconfig fetched at
  runtime. Human never pastes credentials to the agent.

## 7. Kill-switch (human or button-press, never automatic)

| Action | Mechanism | Compute bill | Survives |
|---|---|---|---|
| Sleep (default) | `azure_compute.sh sleep` (`az aks stop`) | ~$0 (VMs deallocated) | Everything: PVCs (postgres/MLflow lineage, MinIO artifacts, Redis), AKS object, ACR, Blob, Flexible |
| Wake | `azure_compute.sh wake` (`az aks start`) | resumes | pods reschedule onto existing disks in minutes |
| Destroy compute | `terraform destroy -target=module.cluster` | $0 compute | ACR, Blob, Flexible, VNet, identities. Lost: in-cluster DBs/artifacts → rehydrate via full deploy (deterministic retrain) |
| Destroy all | `destroy_azure.sh` | $0 total | nothing |

Residual while asleep: disks (pennies) + Blob (pennies) + Flexible B1ms
(~$0.03/hr) — the price of "registry stays".

## 8. Access map

- **Public (Azure LB):** model-api :8080 only.
- **Port-forward (human laptop):** Grafana :3000, Prometheus :9090,
  MLflow :5000, MinIO :9001, drift-monitor :8089. NodePorts are not
  internet-reachable (no node public IPs) — NSG breadth is defense-in-depth
  only, not exposure.

## 9. Known seams (honest, not hidden)

1. Offline store + MLflow artifacts live in **in-cluster MinIO**, not Blob
   (Feast has no native Blob backend; MLflow needs azure extras) — Blob
   containers are provisioned and waiting.
2. Workload-identity subjects for retrain/mlflow point at the `serving`
   namespace and go live only with the Blob cutover.
3. Initial AKS release pins `model.version` explicitly instead of running the
   full gate→staging ceremony (drift loop covers it in-cluster thereafter).
4. `MLP-CLOUD-RG` (old VM design) is empty; next apply reconciles it.
5. B2s is tight on RAM and retiring per region — B2as_v2 is the standing
   recommendation.

## 10. Costs (student grant)

Running (2×B2s): ~$0.08 compute + $0.03 Flexible + $0.006 ACR + <$0.01 Blob +
~$0.025 LB ≈ **~$0.15/hr**. B2as_v2 nodes add ~$0.02–0.04/hr. Asleep: ~$0.04/hr.
Destroyed: $0. Demo windows: sleep by default, destroy when done.
