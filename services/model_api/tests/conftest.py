"""Reusable in-memory providers for model API tests."""

from __future__ import annotations

from collections.abc import Iterator

import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient
from model_api.deps import ModelApiSettings
from model_api.main import create_app

from ml.data.schemas import FEATURE_COLUMNS


class FakeFeatureSource:
    """Small reachable feature source with deterministic rows."""

    def __init__(self, *, reachable: bool = True) -> None:
        """Build three indexed feature rows."""
        self.reachable = reachable
        self.frame = pd.DataFrame(
            {
                name: np.arange(1, 4, dtype="float64") + offset
                for offset, name in enumerate(FEATURE_COLUMNS)
            },
            index=pd.Index([1, 2, 3], name="customer_id"),
        )

    def get(self, ids: list[int]) -> pd.DataFrame:
        """Return known IDs in request order."""
        return self.frame.loc[[item for item in ids if item in self.frame.index]].copy()

    def ping(self) -> bool:
        """Expose the configured reachability state."""
        return self.reachable


class FakeModelSource:
    """Deterministic model returning low, medium, and high risk."""

    version = "test-v7"
    feature_names = FEATURE_COLUMNS

    def predict_proba(self, features: pd.DataFrame) -> np.ndarray:
        """Return a stable probability based on the first feature."""
        positive = np.clip(features.iloc[:, 0].to_numpy() / 4.0, 0.0, 1.0)
        return np.column_stack([1.0 - positive, positive])


@pytest.fixture(scope="module")
def api_client() -> Iterator[TestClient]:
    """Run one application lifespan for the endpoint suite."""
    settings = ModelApiSettings(model_version="test-v7")
    with TestClient(
        create_app(
            settings,
            feature_source=FakeFeatureSource(),
            model_source=FakeModelSource(),
        )
    ) as client:
        yield client
