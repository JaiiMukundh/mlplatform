# Retraining toolbox (P8.4): the training image plus the release toolchain.
# The retrain Job trains (Feast + MLflow), then dispatches the release by
# running the SAME scripts the workflow uses, so it needs kubectl, helm, the
# release scripts, and the charts baked in. Pinned tool versions match
# docs/VERSIONS.md; checksums are verified at build time.
ARG BASE_IMAGE=localhost:5001/training:dev
FROM ${BASE_IMAGE}

# No USER switching for the payload: /app/bin is owned by the image user
# (10001) and keeps everything inside the workdir (hadolint DL3066/DL3045
# stay clean). One root step installs curl for smoke.sh/release REST calls.
WORKDIR /app
ENV PATH=/app/bin:$PATH
# hadolint ignore=DL3066
USER root
# hadolint ignore=DL3008,DL3009
RUN apt-get update && apt-get install -y --no-install-recommends curl jq \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /app/bin && chown 10001:10001 /app/bin
USER 10001:10001

ARG KUBECTL_VERSION=v1.37.1
ARG HELM_VERSION=v3.22.0
ENV KUBECTL_VERSION=${KUBECTL_VERSION} HELM_VERSION=${HELM_VERSION}

COPY --chown=10001:10001 core/retrain/ retrain/
COPY --chown=10001:10001 ops/scripts/model_release_local.sh ops/scripts/deploy.sh ops/scripts/smoke.sh ops/scripts/loadcheck.py ops/scripts/run_gate.sh ops/scripts/run_job.sh ops/scripts/archive/install_k8s_tools.py scripts/
COPY --chown=10001:10001 infra/deploy/charts/model-api deploy/charts/model-api
COPY --chown=10001:10001 infra/deploy/gate deploy/gate

RUN python3 scripts/install_k8s_tools.py

USER 10001:10001
