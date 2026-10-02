"""Tests for local file-backed provider implementations."""

from __future__ import annotations

from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import pytest
from sklearn.dummy import DummyClassifier

from ml.data.schemas import ENTITY_COLUMN, FEATURE_COLUMNS
from model_api.deps import ModelApiSettings, build_feature_source, build_model_source
from model_api.providers.stub import JoblibModelSource, ParquetFeatureSource


def feature_frame() -> pd.DataFrame:
    """Build two canonical feature rows."""
    return pd.DataFrame(
        {
            ENTITY_COLUMN: [1, 2],
            **{
                name: np.array([offset + 1, offset + 2], dtype="float64")
                for offset, name in enumerate(FEATURE_COLUMNS)
            },
        }
    )


def test_parquet_source_preserves_known_request_order(tmp_path: Path) -> None:
    """Unknown IDs are omitted for the API layer to report."""
    path = tmp_path / "features.parquet"
    feature_frame().to_parquet(path, index=False)
    source = ParquetFeatureSource(path)

    result = source.get([2, 999, 1])

    assert result.index.tolist() == [2, 1]
    assert result.columns.tolist() == FEATURE_COLUMNS
    assert source.ping() is True


def test_parquet_source_rejects_duplicate_entities(tmp_path: Path) -> None:
    """Serving files must contain one latest row per customer."""
    path = tmp_path / "duplicate.parquet"
    frame = feature_frame()
    frame.loc[1, ENTITY_COLUMN] = 1
    frame.to_parquet(path, index=False)
    with pytest.raises(ValueError, match="duplicate customer IDs"):
        ParquetFeatureSource(path)


def test_joblib_source_enforces_training_feature_order(tmp_path: Path) -> None:
    """The persisted estimator supplies its exact input schema."""
    frame = feature_frame().set_index(ENTITY_COLUMN)
    classifier = DummyClassifier(strategy="prior").fit(frame, [0, 1])
    path = tmp_path / "model.joblib"
    joblib.dump(classifier, path)

    source = JoblibModelSource(path, version="42")

    assert source.version == "42"
    assert source.feature_names == FEATURE_COLUMNS
    assert source.predict_proba(frame).shape == (2, 2)


def test_provider_factories_fail_loudly_for_unknown_modes() -> None:
    """Unsupported provider names cannot silently fall back to local files."""
    with pytest.raises(ValueError, match="FEATURE_SOURCE"):
        build_feature_source(ModelApiSettings(feature_source="unknown"))
    with pytest.raises(ValueError, match="MODEL_SOURCE"):
        build_model_source(ModelApiSettings(model_source="unknown"))
