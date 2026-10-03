#!/usr/bin/env bash
# Publish the Parquet data Feast needs into the MinIO `feast-offline` bucket.
# Idempotent. Runs on the host and reaches MinIO at localhost:9000 (NodePort 30900).
set -Eeuo pipefail

readonly MC_IMAGE="bitnamilegacy/minio-client:2025.7.21-debian-12-r2@sha256:7a6b4b93998903f1673d2bd2140ac26b807c4224627b743778c5a8f70db561f1"
readonly BUCKET="feast-offline"
readonly ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"

export FEAST_MINIO_USER="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-user}' | base64 -d)"
export FEAST_MINIO_PASSWORD="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-password}' | base64 -d)"
export FEAST_MINIO_ENDPOINT="${ENDPOINT}"
export FEAST_MINIO_BUCKET="${BUCKET}"

# Pass credentials as environment, never interpolate them into executable code.
docker run --rm --network host -v "${PWD}:/work:ro" -w /work \
  -e FEAST_MINIO_USER -e FEAST_MINIO_PASSWORD -e FEAST_MINIO_ENDPOINT \
  -e FEAST_MINIO_BUCKET --entrypoint /bin/bash "${MC_IMAGE}" -c '
set -Eeuo pipefail
mc alias set minio "$FEAST_MINIO_ENDPOINT" "$FEAST_MINIO_USER" "$FEAST_MINIO_PASSWORD" >/dev/null
mc mb --ignore-existing "minio/$FEAST_MINIO_BUCKET" >/dev/null
mc cp /work/data/features.parquet "minio/$FEAST_MINIO_BUCKET/customer_features.parquet"
mc cp /work/data/labels.parquet "minio/$FEAST_MINIO_BUCKET/labels.parquet"
mc ls "minio/$FEAST_MINIO_BUCKET"
'
echo "publish_feast_data: uploaded to ${ENDPOINT}/${BUCKET}"
