# Failure Modes Matrix & Disaster Recovery (P9.4)

Verified against the live cluster on 2026-10-04.

## 1. Component Failure Matrix

| Component | Failure Impact ("When it Dies") | Detection Mechanism | Automated & Manual Recovery |
| :--- | :--- | :--- | :--- |
| **`model-api`** | Loss of serving capacity. If single pod dies, surviving replicas handle traffic (PDB `minAvailable: 1`). If all die, clients receive 502/503. | Kubernetes Liveness probe failure; Prometheus `ModelApiDown` alert (`sum(up{job="model-api"}) == 0`). | **Automated:** Kubernetes ReplicaSet restarts pod. If `ModelApiDown` fires, `remediator` executes `kubectl rollout restart`.<br>**Manual:** `helm rollback model-api -n serving`. |
| **`redis`** | Online feature store unavailable. `POST /predict` cannot hydrate features and fails with 500 (connection failure). When Redis restarts, in-memory cache is empty, returning `unknown_customers` (404). | Health check endpoint; Loki logs `redis.exceptions.ConnectionError`; Prometheus `HighErrorRate` alert. | **Automated:** Deployment restarts pod.<br>**Manual:** `make feast-rematerialize` rewrites full historical window from MinIO into Redis. |
| **`postgres`** | Prediction logging cannot reach database. MLflow metadata cannot update. Model serving **continues uninterrupted** (200 OK) due to in-memory asynchronous batch buffering. | Loki logs `prediction log flush failed`; Prometheus gauge `predlog_flush_failures_total`. | **Automated:** StatefulSet restarts Postgres; `model-api` predlog worker retries with backoff and flushes buffered queue on reconnect.<br>**Manual:** `kubectl rollout restart statefulset/postgres -n data`. |
| **`minio`** | Offline training, Feast materialization, and new MLflow artifact uploads fail. Live inference **unaffected** because runtime features live in Redis and model weights are in pod memory. | Loki logs `EndpointConnectionError`; Jobs fail with non-zero exit. | **Automated:** Kubernetes Deployment restarts MinIO pod; PVC preserves bucket contents.<br>**Manual:** Verify PVC mount and secret `minio-auth`. |
| **`mlflow`** | Model tracking unavailable. If down at `model-api` startup, new pods fail startup probe and enter `CrashLoopBackOff`, preventing traffic routing to broken pods. Surviving pods serve unchanged. | Pod readiness `0/1`; Loki logs `MlflowClient` connection errors; Alertmanager warnings. | **Automated:** Deployment recreates pod; SQLite/Postgres backend remains intact.<br>**Manual:** `kubectl rollout restart deployment/mlflow -n data`. |
| **`drift-monitor`**| Scheduled drift evaluations cease; automated retraining loop paused. Live serving and metrics are completely unaffected. | Prometheus `up{job="drift-monitor"} == 0`; staleness of `model_drift_last_eval_timestamp`. | **Automated:** Deployment recreates monitor pod; state reconstructs on first evaluation cycle.<br>**Manual:** `make deploy-monitor`. |
| **`retrain job`** | Candidate model registration or release fails. Active production champion remains serving with zero regression or disruption. | Kubernetes Job status `Failed`; Prometheus `RetrainFailed` alert. | **Automated:** Job `backoffLimit: 1` cleans up; candidate release aborted.<br>**Manual:** Inspect `kubectl logs job/<name> -n data`; trigger manual retrain with `make train-mlflow`. |
| **`remediator`** | Automated alert response (HPA min scaling, Grafana annotations, emergency restart) ceases. Observability and serving continue normally. | Alertmanager delivery failures logged; `up{job="remediator"} == 0`. | **Automated:** Deployment restarts pod.<br>**Manual:** `helm upgrade --install remediator deploy/charts/remediator -n observability`. |
| **`runner`** | CI/CD automation paused; no automated PR checks or deployments. In-cluster workloads continue unaffected. | GitHub repository Actions runner status shows "Offline". | **Automated:** Systemd service on host restarts runner.<br>**Manual:** Run `scripts/bootstrap.sh` or check runner logs in `/tmp`. |

---

## 2. Empirical Failure-Mode Experiments (Live Verification)

Four core failure scenarios were tested on the live platform (`scripts/verify_failure_modes.sh`):

### Experiment 1: PostgreSQL Down $\rightarrow$ In-Memory Predlog Buffering
- **Action:** Scaled `statefulset/postgres` to 0 replicas.
- **Observed Behavior:**
  - `POST /predict` returned **`HTTP 200 OK`** with valid probability predictions.
  - Serving latency remained $< 15\,\text{ms}$.
  - The `PredictionLogger` worker caught database connection errors, incremented `predlog_flush_failures_total`, and requeued batches into its bounded memory queue without dropping rows.
  - Upon scaling Postgres back to 1 replica, the worker resumed flushing, and all buffered rows were written to `prediction_log`.

### Experiment 2: Redis Down $\rightarrow$ Feature Hydration Failure
- **Action:** Scaled `deployment/redis` to 0 replicas.
- **Observed Behavior:**
  - `POST /predict` immediately failed with **`HTTP 500 Internal Server Error`** (`ConnectionRefusedError`).
  - Upon restoring Redis, the empty cache returned `{"error":"unknown_customers"}` (404).
  - Executed `make feast-rematerialize`, which repopulated Redis from MinIO Parquet files within 14 seconds.
  - `POST /predict` immediately resumed returning **`HTTP 200 OK`**.

### Experiment 3: MLflow Down at Pod Startup $\rightarrow$ Safe Routing Guardrail
- **Action:** Scaled `deployment/mlflow` to 0 replicas, then scaled `deployment/model-api` from 2 to 3 replicas.
- **Observed Behavior:**
  - The new pod failed startup initialization because it could not pull model artifacts from MLflow.
  - The pod remained in `0/1 Running` and failed its startup probe.
  - Kubernetes Endpoint slice **excluded** the new pod from the Service, routing 100% of client traffic to existing healthy pods.
  - Once MLflow was scaled back to 1, the new pod completed startup and became `1/1 Ready` in 13 seconds.

### Experiment 4: MinIO Down $\rightarrow$ Online Serving Resiliency
- **Action:** Scaled `deployment/minio` to 0 replicas.
- **Observed Behavior:**
  - Live prediction traffic on `/predict` and health probes on `/healthz` and `/readyz` continued returning **`HTTP 200 OK`** without degradation.
  - Because model weights are pinned in memory and features are served out of Redis, MinIO outages only impact asynchronous background jobs (retraining / Feast data publishing), not customer-facing inference.
  - Restored MinIO to 1 replica with persistent storage intact.
