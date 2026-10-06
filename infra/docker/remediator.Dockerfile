FROM python:3.11.15-slim-bookworm@sha256:d29f48a31a8b408ed19272ca1e7b10ebae13b240a27e862d3d4217c528e2e0c3 AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build
COPY pyproject.toml README.md ./
COPY core/ core/
RUN python -m pip install --prefix=/install .

FROM python:3.11.15-slim-bookworm@sha256:d29f48a31a8b408ed19272ca1e7b10ebae13b240a27e862d3d4217c528e2e0c3

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --system --gid 10001 mlplatform \
    && useradd --system --uid 10001 --gid mlplatform --home-dir /app mlplatform

WORKDIR /app
COPY --from=builder /install /usr/local

USER 10001:10001
EXPOSE 8080

CMD ["uvicorn", "remediator.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log"]
