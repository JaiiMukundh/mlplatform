FROM python:3.11.15-slim-bookworm@sha256:d29f48a31a8b408ed19272ca1e7b10ebae13b240a27e862d3d4217c528e2e0c3

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Pinned training stack (P6.2/P6.4). Pandas resolves to 2.x via the feast
# constraint; this image is isolated from the serving image (pandas 3).
# psycopg is required for the Feast SQL registry (postgresql+psycopg://).
# pydantic/pydantic-settings carry mlp_common.config + schemas (same pins as
# the root package); the full root package cannot install here (pandas<3).
RUN pip install \
      feast==0.66.0 \
      mlflow==3.16.1 \
      scikit-learn==1.9.1 \
      pyarrow==25.0.1 \
      joblib==1.6.0 \
      boto3==1.43.106 \
      redis==8.1.0 \
      s3fs==2026.9.0 \
      pydantic==2.13.5 \
      pydantic-settings==2.15.0 \
      "psycopg[binary]==3.3.6"

RUN groupadd --system --gid 10001 mlplatform \
    && useradd --system --uid 10001 --gid mlplatform --home-dir /app mlplatform

WORKDIR /app
COPY --chown=10001:10001 core/ml/ ml/
COPY --chown=10001:10001 core/mlp_common/ mlp_common/
COPY --chown=10001:10001 core/feature_repo/ feature_repo/
COPY --chown=10001:10001 ops/scripts/gate.py scripts/gate.py
COPY --chown=10001:10001 pyproject.toml README.md ./

USER 10001:10001
