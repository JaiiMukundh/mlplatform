"""Shared dashboard settings, cached demo model, and action definitions."""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path
from typing import Any

import pandas as pd
from mlp_common.logging import JsonFormatter
from pydantic import BaseModel

logger = logging.getLogger("ui")
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter("dashboard"))
logger.handlers = [handler]
logger.setLevel(logging.INFO)
logger.propagate = False


BASE_DIR = Path(__file__).resolve().parents[1]
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
ACTIVE_DRIFT_QUERY = (
    "max(model_drift_detected and on(instance) up == 1) "
    "or max(model_drift_detected) or vector(0)"
)

# Track running jobs
RUNNING_JOBS: dict[str, dict[str, Any]] = {}

MODEL_API_URL = os.environ.get("MODEL_API_URL", "http://localhost:8080")
PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
MLFLOW_URL = os.environ.get("MLFLOW_TRACKING_URI", "http://localhost:5000")
MINIO_URL = os.environ.get("MINIO_ENDPOINT", "http://localhost:9000")
BASELINE_VERSION = "local"


def load_cloud_demo_data() -> str:
    """Fetch real demo data and the initial model at runtime, never bake them in."""
    import boto3
    import joblib
    import mlflow.sklearn
    from mlflow.tracking import MlflowClient

    data = BASE_DIR / "data"
    artifacts = BASE_DIR / "artifacts"
    data.mkdir(exist_ok=True)
    artifacts.mkdir(exist_ok=True)
    storage = boto3.client("s3", endpoint_url=MINIO_URL)
    for source, target in [
        ("customer_features.parquet", "features.parquet"),
        ("labels.parquet", "labels.parquet"),
    ]:
        storage.download_file("feast-offline", source, str(data / target))
    frame = pd.read_parquet(data / "features.parquet")
    frame.loc[frame.event_timestamp == frame.event_timestamp.max()].to_parquet(
        data / "features_latest.parquet", index=False
    )
    version = MlflowClient(MLFLOW_URL).get_model_version_by_alias(
        "loan-default", "baseline"
    )
    model = mlflow.sklearn.load_model(f"models:/loan-default/{version.version}")
    joblib.dump(model, artifacts / "model.joblib")
    return str(version.version)


if os.environ.get("DEPLOY_TARGET") == "azure":
    BASELINE_VERSION = load_cloud_demo_data()

BASELINE_MODEL = None
try:
    _model_path = BASE_DIR / "artifacts" / "model.joblib"
    if _model_path.exists():
        import joblib

        BASELINE_MODEL = joblib.load(_model_path)
        logger.info("Loaded baseline model from %s", _model_path)
except Exception as _e:
    logger.warning("Could not load baseline model: %s", _e)


ACTION_COMMANDS: dict[str, str] = {
    "reset_demo": "uv run --all-groups python scripts/reset_demo.py",
    "traffic_burst": (
        "uv run --all-groups python scripts/traffic.py --rps 15 --duration 20 --url http://localhost:8080"
    ),
    "chaos_latency_inject": (
        "for p in $(kubectl get pods -n serving -l app.kubernetes.io/name=model-api "
        "-o jsonpath='{.items[*].metadata.name}'); do "
        "kubectl exec -n serving $p -c api -- "
        "curl -s -X POST 'http://localhost:8080/debug/latency?ms=500'; "
        'echo "Injected 500ms latency on $p"; done'
    ),
    "chaos_latency_clear": (
        "for p in $(kubectl get pods -n serving -l app.kubernetes.io/name=model-api "
        "-o jsonpath='{.items[*].metadata.name}'); do "
        "kubectl exec -n serving $p -c api -- "
        "curl -s -X POST 'http://localhost:8080/debug/latency?ms=0'; "
        'echo "Cleared latency on $p"; done'
    ),
    "chaos_pod_kill": "bash scripts/chaos_pod.sh",
    "demo_infra": "bash scripts/chaos_alert.sh",
    "simulate_drift": (
        "uv run --all-groups python scripts/simulate_drift.py --scenario covariate && "
        "uv run --all-groups python scripts/traffic.py --rps 30 --duration 12 --url http://localhost:8080"
    ),
    "auto_heal": (
        "uv run --all-groups python scripts/simulate_drift.py --scenario covariate && "
        "uv run --all-groups python scripts/traffic.py --rps 30 --duration 12 --url http://localhost:8080"
    ),
    "demo_model": "bash scripts/retrain_and_release.sh",
    "manual_retrain": "bash scripts/retrain_and_release.sh",
    "demo_model_full": "bash scripts/retrain_and_release.sh",
    "run_gate": "bash scripts/run_gate.sh",
    "feast_rematerialize": "make feast-rematerialize",
    "e2e_tests": "make e2e",
}


if os.environ.get("DEPLOY_TARGET") == "azure":
    for action, command in ACTION_COMMANDS.items():
        command = command.replace("uv run --all-groups python", "python")
        if action not in {"chaos_latency_inject", "chaos_latency_clear"}:
            command = command.replace("http://localhost:8080", MODEL_API_URL)
        ACTION_COMMANDS[action] = command
    ACTION_COMMANDS["reset_demo"] += f" --version {BASELINE_VERSION}"
    ACTION_COMMANDS["e2e_tests"] = (
        f"bash scripts/smoke.sh serving model-api {MODEL_API_URL}"
    )


class PredictRequest(BaseModel):
    customer_id: str | int = "1"
    env: str = "clean"


class ActionRequest(BaseModel):
    action: str


class BurstTestRequest(BaseModel):
    count: int = 10
