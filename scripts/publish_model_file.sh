#!/usr/bin/env bash
# Publish the runtime model artifacts + features parquet to MinIO ml-data.
# Idempotent. Run via the kind host: reaches MinIO at localhost:9000 (NodePort 30900).
set -Eeuo pipefail

readonly MC_IMAGE="bitnamilegacy/minio-client:2025.7.21-debian-12-r2@sha256:7a6b4b93998903f1673d2bd2140ac26b807c4224627b743778c5a8f70db561f1"
readonly BUCKET="ml-data"
readonly ENDPOINT="${MINIO_ENDPOINT:-http://localhost:9000}"

USER_B64="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-user}')"
PASS_B64="$(kubectl -n data get secret minio-auth -o jsonpath='{.data.root-password}')"
USER="$(printf '%s' "${USER_B64}" | base64 -d)"
PASS="$(printf '%s' "${PASS_B64}" | base64 -d)"

docker run --rm --network host -v "${PWD}:/work" -w /work --entrypoint /bin/bash "${MC_IMAGE}" -c "
set -Eeuo pipefail
mc alias set minio '${ENDPOINT}' '${USER}' '${PASS}' >/dev/null
mc rm --recursive --force 'minio/${BUCKET}/artifacts' >/dev/null || true
for f in /work/artifacts/*; do
  mc cp "\${f}" "minio/${BUCKET}/artifacts/"
done
mc cp /work/data/features_latest.parquet "minio/${BUCKET}/features_latest.parquet"
mc cp /work/data/features.parquet "minio/${BUCKET}/features.parquet"
mc cp /work/data/labels.parquet "minio/${BUCKET}/labels.parquet"
mc ls --recursive "minio/${BUCKET}" | head -n 20
"
echo "publish_model_file: uploaded to ${ENDPOINT} bucket ${BUCKET}"
