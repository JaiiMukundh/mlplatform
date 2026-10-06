# Prediction lineage (P6.8)

How to trace any prediction back to the exact model, data, code, and features
that produced it. Nothing here is simulated: IDs below come from the live
MLflow registry and `prediction_log`.

## Worked example

1. **Prediction row** (`postgres.data.svc:5432/mlp`, table `prediction_log`):

   ```sql
   select request_id, model_version, customer_id, score, ts from prediction_log
   where request_id = 'b29a7440-b930-4fc9-93b6-8a82574f3d58';
   --  customer_id=3, model_version=1, score=0.02981413, ts=2026-10-03 13:57:20Z
   ```

   The `features` column (jsonb) holds the exact six input values scored.
   `request_id` matches the `x-request-id` response header and Loki logs.

2. **Model version** — `GET /model-info` on any serving pod reports
   `version: "1"`, `mlflow_run_id: d43d19658d0c41cdace2f858f4104422`,
   `feature_service: loan_default_v1`,
   `registered_at: 2026-10-03T13:33:00.537000+00:00`.

3. **MLflow run** (`http://localhost:5000`, experiment `loan-default`,
   run `d43d1965...`):
   - params: hyperparameters (`learning_rate=0.08, max_iter=180,
     max_leaf_nodes=31, l2_regularization=0.2, random_state=42`),
     `data_start=2026-09-10`, `data_end=2026-10-01`,
     `feast_feature_service=loan_default_v1`, `git_sha=2b17d1a`,
     `trigger=manual`.
   - metrics: `test_auc=0.8581`, `validation_auc=0.8562` (+ PR-AUC, log-loss,
     Brier, accuracy, positive rate).
   - artifacts: `reference.parquet` (10k train-feature sample — the drift
     baseline), `eval_set.parquet` (temporal test split with labels — the
     release-gate dataset), `model/` (signed cloudpickle sklearn estimator).
   - registered as `loan-default` version `1`, alias `champion`.

4. **Data window** — `data_start`/`data_end` bound the labels used:
   `feast-offline/labels.parquet` rows with
   `2026-09-10 <= event_timestamp <= 2026-10-01`, joined point-in-time
   correctly to `feast-offline/customer_features.parquet` via
   `loan_default_v1` (temporal split 70/15/15, no leakage).

5. **Code** — `git_sha` is the HEAD recorded when `make train-mlflow`
   rendered the Job (`scripts/train_mlflow.sh`). Retrains record their own
   SHA plus `trigger=drift` and `parent_champion` tags, so every version
   maps to the exact training code.

6. **Features** — `feature_service=loan_default_v1` pins
   `feature_repo/definitions.py:customer_features` (six fields, TTL 365d);
   the online values live in Redis, the offline source at
   `s3://feast-offline/customer_features.parquet`.

## Chain summary

`prediction_log.request_id` → `model_version` → MLflow run
(params/metrics/artifacts/tags) → data window + feature service + git SHA →
exact feature values (row `features` jsonb + Redis/MinIO sources).
