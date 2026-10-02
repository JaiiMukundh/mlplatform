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

- Symptom: a `retrain-*` Job failed in `mlops` (critical). Populated in P8.
- Automated: none.
- Human: `kubectl -n mlops logs job/<name>`; check MLflow/MinIO and Feast;
  re-trigger via the drift monitor after fixing the cause.
