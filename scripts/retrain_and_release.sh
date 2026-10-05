#!/usr/bin/env bash
# End-to-end retraining and zero-downtime release script for fast interactive demo.
# 1. Trains candidate model in-cluster via Feast historical retrieval and MLflow.
# 2. Resolves registered candidate version from MLflow registry.
# 3. Executes Quality Gate (AUC >= 0.82, latency <= 20ms).
# 4. Deploys to staging, runs canary load check, promotes to champion, and rolls out to prod.
set -Eeuo pipefail

stamp() { date -u +%FT%TZ; }

echo "======================================================="
echo "[$(stamp)] LAUNCHING RETRAINING & ZERO-DOWNTIME RELEASE"
echo "======================================================="

echo "[STEP 1/3] Triggering in-cluster Feast training Job (TRIGGER=drift)..."
TRIGGER=drift bash scripts/train_mlflow.sh

echo "[STEP 2/3] Resolving registered candidate version from MLflow..."
CANDIDATE_VERSION=$(curl -s "http://localhost:5000/api/2.0/mlflow/registered-models/get?name=loan-default" | python3 -c "import json,sys; a=json.load(sys.stdin)['registered_model'].get('aliases', []); print(next((x['version'] for x in a if x['alias']=='candidate'), ''))")

if [ -z "$CANDIDATE_VERSION" ]; then
    echo "ERROR: No candidate version found in MLflow registry!"
    exit 1
fi
echo "[$(stamp)] Candidate model registered: loan-default v${CANDIDATE_VERSION}"

echo "[STEP 3/3] Running Quality Gate, Staging Canary, and Production Rollout..."
LOADCHECK_TOTAL=300 LOADCHECK_RPS=30 bash scripts/model_release_local.sh "${CANDIDATE_VERSION}" dev

echo "======================================================="
echo "[$(stamp)] RETRAINING COMPLETE: Champion is now v${CANDIDATE_VERSION}"
echo "Zero-downtime rollout completed across all serving replicas."
echo "======================================================="
