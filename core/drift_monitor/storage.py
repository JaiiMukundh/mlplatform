"""Database reads and writes used by the drift monitor."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pandas as pd
from mlp_common.schemas import MODEL_FEATURES
from sqlalchemy import text

if TYPE_CHECKING:
    from mlp_common.drift import DriftReport

    from drift_monitor.main import MonitorState


def _meta_table_ddl() -> str:
    """Return idempotent DDL for persisted monitor counters."""
    return (
        "CREATE TABLE IF NOT EXISTS drift_meta"
        " (key TEXT PRIMARY KEY, value TEXT NOT NULL,"
        " updated_at TIMESTAMPTZ NOT NULL DEFAULT now())"
    )


def load_persisted_state(engine: object, state: MonitorState) -> None:
    """Restore breach counters across monitor restarts."""
    with engine.begin() as connection:  # type: ignore[union-attr]
        connection.execute(text(_meta_table_ddl()))
        rows = connection.execute(text("SELECT key, value FROM drift_meta")).all()
    for key, value in rows:
        if key == "consecutive_breaches":
            state.consecutive_breaches = int(value)
        elif key == "last_trigger_epoch" and value:
            state.last_trigger_epoch = float(value)


def save_persisted_state(engine: object, state: MonitorState) -> None:
    """Persist counters so a restart cannot trigger retraining twice."""
    values = {
        "consecutive_breaches": str(state.consecutive_breaches),
        "last_trigger_epoch": (
            "" if state.last_trigger_epoch is None else str(state.last_trigger_epoch)
        ),
    }
    with engine.begin() as connection:  # type: ignore[union-attr]
        connection.execute(
            text(
                "INSERT INTO drift_meta (key, value, updated_at)"
                " VALUES (:key, :value, now())"
                " ON CONFLICT (key) DO UPDATE SET value=:value, updated_at=now()"
            ),
            [{"key": key, "value": value} for key, value in values.items()],
        )


def save_feature_state(engine: object, report: DriftReport) -> None:
    """Persist per-feature PSI in the chart-owned drift_state table."""
    with engine.begin() as connection:  # type: ignore[union-attr]
        for item in report.features:
            connection.execute(
                text(
                    "INSERT INTO drift_state (feature, psi, threshold, updated_at)"
                    " VALUES (:feature, :psi, :threshold, now())"
                    " ON CONFLICT (feature) DO UPDATE SET psi=:psi,"
                    " threshold=:threshold, updated_at=now()"
                ),
                {"feature": item.feature, "psi": item.psi, "threshold": 0.25},
            )


def fetch_window(engine: object, version: str, limit: int) -> pd.DataFrame:
    """Load the newest prediction features scored by one model version."""
    with engine.connect() as connection:  # type: ignore[union-attr]
        rows = connection.execute(
            text(
                "SELECT features FROM prediction_log"
                " WHERE model_version = :version ORDER BY id DESC LIMIT :limit"
            ),
            {"version": version, "limit": limit},
        ).all()
    records = [
        row[0] if isinstance(row[0], dict) else json.loads(row[0]) for row in rows
    ]
    return pd.DataFrame(records, columns=MODEL_FEATURES)
