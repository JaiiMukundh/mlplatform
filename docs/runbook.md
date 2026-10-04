# Runbook

Operational responses for each alert. Alerts are defined in
`deploy/charts/observability/templates/alerts.yaml`; automated actions are
performed by the remediator (`remediator/`, `scripts/chaos_alert.sh` drill).

## ModelApiDown

- Symptom: `sum(up{job="model-api"}) == 0` for 1m (critical).
- Automated: remediator creates a Grafana annotation and triggers a rollout
  restart of `model-api` in `serving`.
- Human: if restarts loop, check `kubectl -n serving get pods`,
  `kubectl -n serving logs deploy/model-api`, and the MinIO `ml-data`
  artifacts + `minio-model` secret (init container fetch failures block startup).

## PodCrashLooping

- Symptom: `increase(kube_pod_container_status_restarts_total{namespace="serving"}[10m]) > 2` (warning).
- Automated: remediator creates a Grafana annotation.
- Human: inspect crashing pod logs; common causes are bad image tags and
  missing model files. Roll back with `helm rollback model-api -n serving`.

## HighErrorRate

- Symptom: 5xx ratio > 5% for 2m (critical).
- Automated: none (page the human). Check prediction logs and recent deploys.
- Human: `helm rollback model-api -n serving` if correlated with a release;
  otherwise inspect `model-api` logs in Grafana Explore (Loki).

## HighP95Latency

- Symptom: `/predict` p95 > 300ms for 1m (warning).
- Automated: remediator raises the `model-api` HPA `minReplicas` by 2
  (capped at HPA max) and annotates Grafana.
- Human: confirm with `scripts/chaos_alert.sh` drill; if latency is from
  injected chaos, reset via `POST /debug/latency?ms=0` on each pod.
  If organic, check traffic (`scripts/traffic.py`) and scale/HPA.

## ModelDriftDetected

- Symptom: `max(model_drift_detected) == 1` for 1m (warning). Populated in P8.
- Automated: annotation only; retraining is already automatic (P8).
- Human: see the ML Health dashboard and `docs/lineage.md` (P6.8).

## RetrainFailed

- Symptom: a `retrain-*` Job failed in `data` (critical).
- Automated: none.
- Human: `kubectl -n data logs job/<name>`; check MLflow/MinIO and Feast;
  re-trigger via the drift monitor after fixing the cause.

## Clean-Room Disaster Recovery & Platform Rebuild (P9.2)

To reconstruct the entire platform from zero state on a fresh host:

```bash
make down && make up && make deploy-all && make e2e
```

### Measured Timing & Milestones (2026-10-04)

Total wall-clock duration: **18m 46s** (automated, zero human interventions).

1. `make down` (~15s): OpenTofu destroys resources, deletes Kind cluster and local registry.
2. `make up` (~9m 20s): OpenTofu provisions 3-node Kind cluster, builds & pushes bootstrap `mlflow:dev` image, deploys Postgres, MinIO, Redis, MLflow, metrics-server, and the kube-prometheus stack, Loki, Alloy, and dashboards.
3. `make deploy-all` (~2m 10s): Builds & pushes all service images (`model-api`, `training`, `remediator`, `drift-monitor`, `retrain`), creates namespaces, deploys remediator, seeds Feast offline store, materializes Redis, trains baseline MLflow champion v1 & candidate v2, deploys `model-api`, deploys drift monitor, and resets demo baseline.
4. `make e2e` (~8m 26s): Runs the full end-to-end test suite (`test_serving_survives_pod_deletion`, `test_model_self_healing_loop`, `test_serving_contract`). All 3 test suites PASS.
