FROM python:3.11.15-slim-bookworm@sha256:d29f48a31a8b408ed19272ca1e7b10ebae13b240a27e862d3d4217c528e2e0c3

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Pinned training stack (P6.4). Pandas resolves to 2.x via the feast
# constraint; this image is isolated from the serving image (pandas 3).
RUN pip install \
      feast==0.66.0 \
      mlflow==3.16.1 \
      scikit-learn==1.9.1 \
      pyarrow==25.0.1 \
      joblib==1.6.0 \
      boto3==1.43.107 \
      redis==8.1.0

RUN groupadd --system --gid 10001 mlplatform \
    && useradd --system --uid 10001 --gid mlplatform --home-dir /app mlplatform

WORKDIR /app
COPY --chown=10001:10001 ml/ ml/
COPY --chown=10001:10001 mlp_common/ mlp_common/
COPY --chown=10001:10001 feature_repo/ feature_repo/
COPY --chown=10001:10001 pyproject.toml README.md ./

USER 10001:10001
