# Autonomous Self-Healing Machine Learning Platform

[![CI Pipeline](https://img.shields.io/badge/CI%2FCD-Passing-brightgreen)]()
[![Kubernetes](https://img.shields.io/badge/Kubernetes-Kind%20v1.37-blue)]()
[![Terraform](https://img.shields.io/badge/IaC-Terraform%20v1.9-purple)]()
[![Feast](https://img.shields.io/badge/Feature%20Store-Feast%20v0.44-orange)]()
[![MLflow](https://img.shields.io/badge/Registry-MLflow%20v2.18-teal)]()
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey)]()

An enterprise-grade, closed-loop machine learning platform running entirely on Kubernetes with full Azure cloud parity. The platform serves high-throughput loan default predictions with sub-15ms latency, enforces mathematical training-serving feature parity, and provides dual-layer self-healing: automated infrastructure remediation for latency spikes and autonomous retraining when statistical feature drift is detected.

---

## 1. System Architecture Overview

![Architecture Diagram](docs/architecture.png)

The platform is organized across three decoupled Kubernetes namespaces:

* **`serving` (Inference & Ingress):**
  * `model-api`: FastAPI microservice running under Horizontal Pod Autoscaler (2..6 replicas). At startup, pods pull pinned model artifacts from MLflow and connect to Redis for online features.
  * In-memory async worker queue buffers prediction records, flushing micro-batches to PostgreSQL without blocking the request path.
  * Hardened with UID `10001:10001`, read-only root filesystems, and default-deny Kubernetes NetworkPolicies.
* **`data` (Feature Store, Storage & Registry):**
  * **Feast Feature Store:** Redis 7.2 online store ($<2$ms hydration) paired with MinIO S3 offline store for point-in-time correct historical joins (zero future data leakage).
  * **MLflow 2.18:** Central model registry tracking model versions, metadata, and frozen baseline distributions (`reference.parquet`).
  * **PostgreSQL 16:** Relational store persisting `prediction_log`, `drift_state`, and `labels_log`.
  * **Retrain Engine:** Ephemeral Kubernetes batch Jobs executing automated LightGBM retraining.
* **`observability` (Monitoring & Automated Remediation):**
  * **Prometheus & Alertmanager:** Scrapes metrics via ServiceMonitors; evaluates latency, error, and drift rules.
  * **Loki & Grafana Alloy:** Aggregates structured JSON logs across all namespaces.
  * **Grafana 11.5:** Pre-provisioned with 3 command dashboards: *Service Health*, *Logs Explorer*, and *ML Platform Health*.
  * **Remediator Webhook:** Automated event listener responding to Prometheus alerts by dynamically scaling HPA floors and emitting Grafana timeline annotations.

---

## 2. The Three Operational Flows

1. **Flow A — Serving (Request Path):**
   Client $\rightarrow$ `POST /predict` $\rightarrow$ `model-api` hydrates credit features from Redis $\rightarrow$ evaluates in-memory pinned model $\rightarrow$ enqueues record to async buffer $\rightarrow$ returns probability $\rightarrow$ background thread flushes to Postgres.
2. **Flow B — Infrastructure Self-Healing:**
   Traffic burst / latency chaos $\rightarrow$ P95 latency exceeds 300ms SLA $\rightarrow$ Prometheus fires `HighP95Latency` $\rightarrow$ Alertmanager calls `remediator` webhook $\rightarrow$ Remediator automatically scales HPA `minReplicas` (2 $\rightarrow$ 4) and annotates Grafana $\rightarrow$ latency normalizes.
3. **Flow C — Autonomous Model Self-Healing (Closed Loop):**
   Feature drift introduced in traffic $\rightarrow$ `drift-monitor` detects PSI > 0.20 across consecutive evaluation windows $\rightarrow$ spawns Kubernetes batch Job $\rightarrow$ Job executes Feast point-in-time join and trains new model $\rightarrow$ registers `candidate` in MLflow $\rightarrow$ passes Quality Gate (AUC floor, non-regression, schema check) $\rightarrow$ 2,000-request staging load check $\rightarrow$ promotes to `champion` $\rightarrow$ zero-downtime rolling update on production $\rightarrow$ drift resolves and loop closes.

---

## 3. Quickstart & One-Command Setup

### 3.1 Host Prerequisites
* **OS:** Linux or macOS (Target machine: 8 CPU, 16 GB RAM).
* **CLI Tools:** Docker (or containerd), Kind, Terraform (`terraform`), Helm, Python 3.11+, `uv`, `curl`, `jq`.
* Verify host prerequisites:
  ```bash
  make bootstrap
  ```
* **Azure (cloud path only):** Azure CLI (`az login`) for the `infra/envs/azure` VM host. See [`ops/docs/azure-port.md`](ops/docs/azure-port.md).

### 3.2 Platform Bootstrap & Deployment
Provision the local 3-node Kubernetes cluster, Terraform data services, observability stack, and deploy all microservices from zero state:
```bash
make up && make deploy-all
```
*(Total automated deployment duration: ~11 minutes).*

### 3.3 Run End-to-End Test Suite
Verify serving contracts, pod chaos resilience, and the closed-loop model retraining loop:
```bash
make e2e
```
*(All 3 test suites pass unattended).*

---

## 4. Web Dashboards & Interactive Interfaces

Ensure port-forwards are active (run `make forward` if using background tunnels):

| Service | Local URL | Credentials / Notes | Purpose |
|---|---|---|---|
| **FastAPI Swagger UI** | `http://localhost:8080/docs` | None (Direct Access) | Interactive API exploration and prediction testing |
| **Grafana Dashboards** | `http://localhost:3000` | `admin` / `admin` | Service Health, Loki Logs, and ML Platform Health dashboards |
| **MLflow Registry** | `http://localhost:5000` | None (Direct Access) | Experiment runs, model artifacts, and `champion`/`candidate` aliases |
| **MinIO Console** | `http://localhost:9001` | `minioadmin` / `minioadmin` | S3 bucket explorer for Parquet datasets and model files |
| **Prometheus UI** | `http://localhost:9090` | None (Direct Access) | PromQL query engine and active alert rules |
| **Alertmanager UI** | `http://localhost:9093` | None (Direct Access) | Alert routing and remediation webhook status |

---

## 5. Live Demonstration Scripts

### 5.1 Reset Demo to Pristine Baseline
Before presenting, restore clean baseline state (wipes Redis, seeds 10,000 baseline customers, verifies champion v2, zeroes drift gauges):
```bash
make reset-demo
```

### 5.2 Demonstrate Infrastructure Self-Healing (Flow B)
Inject artificial latency chaos and watch Prometheus trigger automated HPA scaling:
```bash
make demo-infra
```
*Watch Grafana Service Health: P95 latency spikes, HPA scales 2 $\rightarrow$ 4 pods, and remediator annotation appears on the timeline.*

### 5.3 Demonstrate Autonomous Model Retraining (Flow C)
Simulate customer feature drift and watch the closed-loop retraining cycle execute:
```bash
make demo-model
```
*Watch Grafana ML Health: PSI spikes past 0.20, Kubernetes spawns retrain Job, candidate passes staging gate, production updates to new model version, and drift metric returns to green.*

---

## 6. Repository Layout Map

```
mlplatform/
├── core/                   # Python services (model_api, drift_monitor, retrain, remediator, ml, mlp_common)
│   └── feature_repo/       # Feast Feature Store definitions (entities, feature views, services)
├── infra/
│   ├── docker/             # Production Dockerfiles (non-root 10001:10001)
│   ├── deploy/
│   │   └── charts/         # Helm charts (model-api, remediator, drift-monitor, retrain, postgres, minio, redis)
│   ├── envs/
│   │   ├── local/          # Terraform Kind cluster and local services
│   │   └── azure/          # Terraform Azure cloud host (VM + VNet + NSG)
│   └── modules/            # Reusable Terraform infrastructure modules (registry, cluster_kind, platform_services, observability)
├── ops/
│   ├── scripts/            # Automation scripts (deploy_all, chaos, smoke, traffic, reset, deploy_azure)
│   ├── ui/                 # Central Management and Demo Dashboard
│   └── docs/               # Full documentation pack (see below)
└── tests/                  # Pytest test suite (unit, parity, e2e)
```

---

## 7. Operational Runbook & Troubleshooting

### 7.1 Rebuilding the Platform from Scratch
To perform an unattended, clean-room disaster recovery rebuild:
```bash
make down && make up && make deploy-all && make e2e
```
*(Verified disaster recovery timing: 18 minutes 46 seconds).*

### 7.2 Common Diagnostic Commands
* **Check pod health across namespaces:**
  ```bash
  kubectl get pods -A
  ```
* **Restore dropped port forwards:**
  ```bash
  make forward
  ```
* **Re-materialize Redis feature cache from offline Parquet:**
  ```bash
  make feast-rematerialize
  ```
* **Inspect real-time serving logs:**
  ```bash
  kubectl logs -n serving deploy/model-api -c api -f
  ```
* **Query PostgreSQL prediction log:**
  ```bash
  kubectl exec -n data statefulset/postgres -- psql -U mlp -d mlp -c "SELECT count(*) FROM prediction_log;"
  ```

---

## 8. Azure Cloud Port & Cost Governance

The platform ports straight to Azure on AKS via `infra/envs/azure` (Terraform `azurerm`), mirroring the old AWS design 1:1 — EKS→AKS, VPC→VNet, S3→Blob Storage, RDS→PostgreSQL Flexible Server, ECR→ACR, IRSA→Workload Identity:
* **Compute & orchestration:** AKS (OIDC + workload identity, 2× `B2s` nodes); serving deploys via Helm with `infra/deploy/charts/model-api/values-azure.yaml` (ACR image, Azure LoadBalancer, workload-identity ServiceAccount).
* **Data:** Flexible Server `B1ms` (private VNet) for app data; Blob containers for artifacts/offline features; MinIO stays in-cluster on AKS for the Feast offline store (Feast has no native Blob backend).
* **Cost Governance:** Estimated **~\$0.15 / hour** (~\$0.45 per 3-hour demo window on the student grant) with a \$50 monthly budget alarm wiring email alerts.
* **Student sizing:** AKS is 2 × 2-vCPU nodes = the ~4 vCPU edu cap exactly (`Standard_B2s` default, `B2as_v2` fallback if your region retired v1). 1 GB SKUs cannot run AKS — enforced by Terraform validation, checked by `make azure-preflight`.
* **Kill-switch:** `bash ops/scripts/azure_compute.sh sleep` stops VM billing and keeps everything (registry/state on PVCs + Blob/Flexible); `wake` resumes. Full teardown via `bash ops/scripts/destroy_azure.sh`.
* **Full training on AKS:** `TAG=v1.0.0 bash ops/scripts/deploy_azure_full.sh` deploys the whole platform (Feast + MLflow + training Jobs) with ACR images — same charts as local.
* Refer to [`ops/docs/azure-port.md`](ops/docs/azure-port.md) (`make azure-init/validate/plan`, `[HUMAN]` `bash ops/scripts/deploy_azure.sh`, teardown via `bash ops/scripts/destroy_azure.sh`).
# GitHub migration status

Local functionality is the tested baseline. Azure provisioning remains a human operation; GitHub-hosted deployment replaces the laptop runner in the next migration task. Use `make lint test check-infra secret-scan` to verify repository changes. Use `make github-login` for account authentication and `make github-push` to publish the current branch. Neither target provisions Azure resources.
