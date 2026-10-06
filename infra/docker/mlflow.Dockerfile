FROM python:3.11.15-slim-bookworm@sha256:d29f48a31a8b408ed19272ca1e7b10ebae13b240a27e862d3d4217c528e2e0c3

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN pip install \
      mlflow==3.16.1 \
      "psycopg[binary]==3.3.6" \
      boto3==1.43.107

RUN groupadd --system --gid 10001 mlplatform \
    && useradd --system --uid 10001 --gid mlplatform --home-dir /app mlplatform

WORKDIR /app
USER 10001:10001
EXPOSE 5000
