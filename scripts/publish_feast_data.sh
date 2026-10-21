#!/usr/bin/env bash
# Upload generated Feast Parquet data to the cloud MinIO service via runner port-forward.
set -Eeuo pipefail
[[ "${DEPLOY_TARGET:-}" == azure ]] || { echo "DEPLOY_TARGET=azure is required" >&2; exit 2; }

export FEAST_MINIO_USER="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-user}' | base64 -d)"
export FEAST_MINIO_PASSWORD="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-password}' | base64 -d)"
export FEAST_MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"

python - <<'UPLOAD'
import boto3
import os

storage = boto3.client(
    "s3",
    endpoint_url=os.environ["FEAST_MINIO_ENDPOINT"],
    aws_access_key_id=os.environ["FEAST_MINIO_USER"],
    aws_secret_access_key=os.environ["FEAST_MINIO_PASSWORD"],
)
for source, key in [
    ("features.parquet", "customer_features.parquet"),
    ("labels.parquet", "labels.parquet"),
]:
    storage.upload_file("data/" + source, "feast-offline", key)
UPLOAD
echo "Published generated features to cloud MinIO"
