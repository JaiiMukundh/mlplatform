"""Drift monitor service (P8.2/P8.3/P8.5).

Evaluates the serving feature distribution against the champion's MLflow
reference every ``DRIFT_INTERVAL_SECONDS``: breach counters, cooldown, and
the active-Job check gate retrain Job creation, and every cycle exports the
gauges the ML Health dashboard and the ``ModelDriftDetected`` alert consume.

Serves ``/metrics`` (Prometheus), ``/healthz`` (liveness), and ``/state``
(last report as JSON).
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass

import pandas as pd
from fastapi import FastAPI, Response
from mlp_common.config import DriftSettings
from mlp_common.drift import DriftReport
from mlp_common.logging import configure_logging
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    CollectorRegistry,
    Counter,
    Gauge,
    generate_latest,
)
from sqlalchemy import create_engine

from drift_monitor.detector import evaluate_window
from drift_monitor.jobs import (
    create_retrain_job as _create_retrain_job,
)
from drift_monitor.jobs import (
    job_terminal as job_terminal,
)
from drift_monitor.jobs import (
    retrain_in_flight as _retrain_in_flight,
)
from drift_monitor.jobs import (
    update_auc_gauges as _update_auc_gauges,
)
from drift_monitor.storage import (
    fetch_window as _fetch_window,
)
from drift_monitor.storage import (
    load_persisted_state as _load_persisted_state,
)
from drift_monitor.storage import (
    save_feature_state as _save_feature_state,
)
from drift_monitor.storage import (
    save_persisted_state as _save_persisted_state,
)
from drift_monitor.trigger import decide

LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class DriftMetrics:
    """All metric collectors owned by one monitor instance."""

    registry: CollectorRegistry
    psi: Gauge
    ks_d: Gauge
    drift_detected: Gauge
    window_samples: Gauge
    last_eval: Gauge
    retrain_triggered: Counter
    champion_auc: Gauge
    candidate_auc: Gauge


def create_metrics() -> DriftMetrics:
    """Create an isolated registry so test applications never collide."""
    registry = CollectorRegistry()
    return DriftMetrics(
        registry=registry,
        psi=Gauge(
            "model_feature_psi",
            "Population Stability Index per feature versus the champion reference.",
            ["feature"],
            registry=registry,
        ),
        ks_d=Gauge(
            "model_feature_ks_d",
            "Kolmogorov-Smirnov D per feature versus the champion reference.",
            ["feature"],
            registry=registry,
        ),
        drift_detected=Gauge(
            "model_drift_detected",
            "1 when the current window breaches the drift rule.",
            registry=registry,
        ),
        window_samples=Gauge(
            "model_drift_window_samples",
            "Prediction rows scored in the last evaluation.",
            registry=registry,
        ),
        last_eval=Gauge(
            "model_drift_last_eval_timestamp",
            "Unix time of the last drift evaluation.",
            registry=registry,
        ),
        retrain_triggered=Counter(
            "retrain_triggered_total",
            "Retrain Jobs created by the drift monitor.",
            registry=registry,
        ),
        champion_auc=Gauge(
            "model_champion_auc",
            "Test AUC of the champion version.",
            registry=registry,
        ),
        candidate_auc=Gauge(
            "model_candidate_auc",
            "Test AUC of the candidate version (0 when none).",
            registry=registry,
        ),
    )


class MonitorSettings(DriftSettings):
    """Environment contract for the drift monitor."""

    database_url: str = "postgresql+psycopg://mlp:mlp@postgres.data.svc:5432/mlp"
    mlflow_tracking_uri: str = "http://mlflow.data.svc:5000"
    jobs_namespace: str = "data"
    template_configmap: str = "retrain-job-template"
    retrain_image: str = "localhost:5001/retrain:dev"


@dataclass
class MonitorState:
    """Mutable evaluation state owned by one monitor process."""

    champion_version: str | None = None
    report: DriftReport | None = None
    consecutive_breaches: int = 0
    last_trigger_epoch: float | None = None
    window_samples: int = 0
    insufficient_data: bool = True
    last_eval_epoch: float = 0.0


def _champion_version(tracking_uri: str) -> str:
    """Resolve the champion alias through MLflow (SPEC: alias is truth)."""
    from mlflow.tracking import MlflowClient

    client = MlflowClient(tracking_uri)
    return str(client.get_model_version_by_alias("loan-default", "champion").version)


def _reference_frame(
    tracking_uri: str, version: str, cache: dict[str, pd.DataFrame]
) -> pd.DataFrame:
    """Download the champion run's reference.parquet, cached by version."""
    if version not in cache:
        from mlflow.tracking import MlflowClient

        client = MlflowClient(tracking_uri)
        meta = client.get_model_version("loan-default", version)
        local_path = client.download_artifacts(
            meta.run_id or "", "reference.parquet", "/tmp"
        )
        cache[version] = pd.read_parquet(local_path)
    return cache[version]


def evaluate_once(
    *,
    settings: MonitorSettings,
    engine: object,
    metrics: DriftMetrics,
    state: MonitorState,
    reference_cache: dict[str, pd.DataFrame],
    now_epoch: float,
) -> None:
    """Run one full detect-decide-trigger cycle (also drives live tests)."""
    version = _champion_version(settings.mlflow_tracking_uri)
    state.champion_version = version
    reference = _reference_frame(settings.mlflow_tracking_uri, version, reference_cache)
    window = _fetch_window(engine, version, settings.drift_window_size)
    state.window_samples = len(window)
    metrics.window_samples.set(len(window))
    metrics.last_eval.set(now_epoch)
    state.last_eval_epoch = now_epoch

    samples_ok = len(window) >= settings.drift_min_samples
    state.insufficient_data = not samples_ok
    if samples_ok:
        report = evaluate_window(
            reference,
            window,
            psi_threshold=settings.drift_psi_threshold,
            ks_d_threshold=settings.drift_ks_d_threshold,
            ks_p_threshold=settings.drift_ks_p,
            min_features=settings.drift_min_features,
        )
    else:
        report = DriftReport(drifted=False, drifted_features=[], features=[])
    state.report = report
    metrics.drift_detected.set(1.0 if report.drifted else 0.0)
    for item in report.features:
        metrics.psi.labels(item.feature).set(item.psi)
        metrics.ks_d.labels(item.feature).set(item.ks_d)
    if samples_ok:
        _save_feature_state(engine, report)

    decision = decide(
        breached=report.drifted,
        consecutive_breaches=state.consecutive_breaches,
        last_trigger_epoch=state.last_trigger_epoch,
        now_epoch=now_epoch,
        retrain_active=(
            _retrain_in_flight(settings.jobs_namespace) if report.drifted else False
        ),
        samples_ok=samples_ok,
        consecutive_required=settings.drift_consecutive,
        cooldown_seconds=settings.retrain_cooldown_seconds,
    )
    state.consecutive_breaches = decision.consecutive_breaches
    if decision.fire:
        _create_retrain_job(
            champion_version=version,
            drift_report=report,
            settings=settings,
        )
        state.last_trigger_epoch = now_epoch
        metrics.retrain_triggered.inc()
    _save_persisted_state(engine, state)
    _update_auc_gauges(settings.mlflow_tracking_uri, metrics)
    LOGGER.info(
        "drift evaluation",
        extra={
            "version": version,
            "drifted": report.drifted,
            "features": ",".join(report.drifted_features),
            "samples": len(window),
            "decision": decision.reason,
        },
    )


def create_app(
    settings: MonitorSettings | None = None,
    *,
    metrics: DriftMetrics | None = None,
) -> FastAPI:
    """Build the monitor application with injectable settings for tests."""
    config = settings or MonitorSettings()
    configure_logging(config.service_name, config.log_level)
    owned_metrics = metrics or create_metrics()
    state = MonitorState()

    async def evaluation_loop() -> None:
        engine = create_engine(config.database_url, pool_pre_ping=True)
        reference_cache: dict[str, pd.DataFrame] = {}
        while True:
            try:
                await asyncio.to_thread(
                    evaluate_once,
                    settings=config,
                    engine=engine,
                    metrics=owned_metrics,
                    state=state,
                    reference_cache=reference_cache,
                    now_epoch=time.time(),
                )
            except Exception:
                LOGGER.exception("drift evaluation failed")
            await asyncio.sleep(config.drift_interval_seconds)

    from contextlib import asynccontextmanager

    @asynccontextmanager
    async def lifespan(_: FastAPI):  # type: ignore[no-untyped-def]
        engine = create_engine(config.database_url, pool_pre_ping=True)
        # Initialization belongs to application startup.  If the database is
        # unavailable, fail the process instead of serving a healthy pod with
        # a silently dead evaluation task.
        await asyncio.to_thread(_load_persisted_state, engine, state)
        LOGGER.info("drift monitor evaluation loop started")
        task = asyncio.create_task(evaluation_loop())
        try:
            yield
        finally:
            task.cancel()
            engine.dispose()

    application = FastAPI(title="MLPlatform drift monitor", lifespan=lifespan)
    application.state.settings = config
    application.state.metrics = owned_metrics
    application.state.monitor = state

    @application.get("/healthz")
    async def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @application.get("/metrics")
    async def prometheus_metrics() -> Response:
        return Response(
            content=generate_latest(owned_metrics.registry),
            media_type=CONTENT_TYPE_LATEST,
        )

    @application.get("/state")
    async def monitor_state() -> dict[str, object]:
        report = state.report
        return {
            "champion_version": state.champion_version,
            "drifted": report.drifted if report else False,
            "drifted_features": report.drifted_features if report else [],
            "features": (
                [
                    {
                        "feature": item.feature,
                        "psi": item.psi,
                        "ks_d": item.ks_d,
                        "ks_p": item.ks_p,
                        "drifted": item.drifted,
                    }
                    for item in report.features
                ]
                if report
                else []
            ),
            "consecutive_breaches": state.consecutive_breaches,
            "last_trigger": state.last_trigger_epoch,
            "window_samples": state.window_samples,
            "insufficient_data": state.insufficient_data,
        }

    return application


app = create_app()
