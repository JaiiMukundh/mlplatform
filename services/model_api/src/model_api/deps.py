"""Settings and provider construction for the serving application."""

from __future__ import annotations

from pathlib import Path

from mlp_common.config import ServiceSettings

from model_api.providers.base import FeatureSource, ModelSource
from model_api.providers.stub import JoblibModelSource, ParquetFeatureSource


class ModelApiSettings(ServiceSettings):
    """Environment contract for the model API."""

    service_name: str = "model-api"
    model_name: str = "loan-default"
    model_version: str = "file-v1"
    model_source: str = "file"
    feature_source: str = "parquet"
    model_path: Path = Path("artifacts/model.joblib")
    feature_path: Path = Path("data/features_latest.parquet")
    database_url: str | None = None
    enable_chaos: bool = False


def build_feature_source(settings: ModelApiSettings) -> FeatureSource:
    """Construct the configured feature provider or fail loudly."""
    if settings.feature_source != "parquet":
        raise ValueError(f"unsupported FEATURE_SOURCE={settings.feature_source}")
    return ParquetFeatureSource(settings.feature_path)


def build_model_source(settings: ModelApiSettings) -> ModelSource:
    """Construct the configured model provider or fail loudly."""
    if settings.model_source != "file":
        raise ValueError(f"unsupported MODEL_SOURCE={settings.model_source}")
    return JoblibModelSource(settings.model_path, version=settings.model_version)
