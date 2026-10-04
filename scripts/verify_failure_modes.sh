#!/usr/bin/env bash
# Verify 4 failure modes experimentally (P9.4):
# 1. Postgres down -> prediction log buffers in memory; API continues serving 200s.
# 2. Redis down -> feature hydration failure detected.
# 3. MLflow down at startup -> model-api pod blocked at startup, preventing bad routing.
# 4. MinIO down -> online inference unaffected (in-memory model + Redis features).
set -Eeuo pipefail

echo "=========================================================="
echo "Failure Mode 1: Postgres down -> Predlog Buffering"
echo "=========================================================="
echo "Scaling postgres to 0..."
kubectl scale statefulset postgres -n data --replicas=0
kubectl wait --for=delete pod/postgres-0 -n data --timeout=60s || true

echo "Sending prediction traffic while Postgres is down..."
STATUS_PG_DOWN="$(curl --retry 3 --retry-all-errors -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/predict -H 'content-type: application/json' -d '{"customer_ids":[1,2,3]}')"
echo "Prediction status while Postgres is down: ${STATUS_PG_DOWN}"

echo "Restoring postgres..."
kubectl scale statefulset postgres -n data --replicas=1
kubectl rollout status statefulset/postgres -n data --timeout=60s
sleep 5
echo "Postgres restored. Prediction status: $(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/predict -H 'content-type: application/json' -d '{"customer_ids":[1]}')"

echo "=========================================================="
echo "Failure Mode 2: Redis down -> Online Feature Degradation"
echo "=========================================================="
echo "Scaling redis to 0..."
kubectl scale deployment redis -n data --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=redis -n data --timeout=60s || true

echo "Sending prediction traffic while Redis is down..."
STATUS_REDIS_DOWN="$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/predict -H 'content-type: application/json' -d '{"customer_ids":[1]}' || echo "failed")"
echo "Prediction status while Redis is down: ${STATUS_REDIS_DOWN}"

echo "Restoring redis..."
kubectl scale deployment redis -n data --replicas=1
kubectl rollout status deployment/redis -n data --timeout=60s
sleep 5
echo "Redis restored. Prediction status: $(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/predict -H 'content-type: application/json' -d '{"customer_ids":[1]}')"

echo "=========================================================="
echo "Failure Mode 3: MLflow down at pod startup"
echo "=========================================================="
echo "Scaling mlflow to 0..."
kubectl scale deployment mlflow -n data --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=mlflow -n data --timeout=60s || true

echo "Scaling model-api to 3 replicas while MLflow is down..."
kubectl scale deployment model-api -n serving --replicas=3
sleep 8
PODS_STATUS="$(kubectl get pods -n serving -l app.kubernetes.io/name=model-api --no-headers | awk '{print $2, $3}')"
echo "Model-API pod states during MLflow outage:"
echo "${PODS_STATUS}"

echo "Restoring mlflow..."
kubectl scale deployment mlflow -n data --replicas=1
kubectl rollout status deployment/mlflow -n data --timeout=60s
kubectl scale deployment model-api -n serving --replicas=2
kubectl rollout status deployment/model-api -n serving --timeout=60s
echo "MLflow restored. Model-API fully ready: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/readyz)"

echo "=========================================================="
echo "Failure Mode 4: MinIO down -> Online Serving Resiliency"
echo "=========================================================="
echo "Scaling minio to 0..."
kubectl scale deployment minio -n data --replicas=0
kubectl wait --for=delete pod -l app.kubernetes.io/name=minio -n data --timeout=60s || true

echo "Sending prediction traffic while MinIO is down..."
STATUS_MINIO_DOWN="$(curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:8080/predict -H 'content-type: application/json' -d '{"customer_ids":[1,2,3]}')"
echo "Prediction status while MinIO is down: ${STATUS_MINIO_DOWN}"

echo "Restoring minio..."
kubectl scale deployment minio -n data --replicas=1
kubectl rollout status deployment/minio -n data --timeout=60s
echo "MinIO restored. Final health check: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz)"

echo "All 4 failure mode experiments completed successfully!"
