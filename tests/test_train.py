"""Tests for temporal splitting and Feast training inputs."""

import datetime as dt
from pathlib import Path

import pandas as pd
from ml.data.generate import generate_dataset, write_dataset
from ml.data.schemas import ENTITY_COLUMN, TIMESTAMP_COLUMN
from ml.train import (
    build_entity_frame,
    temporal_split,
)


def test_temporal_split_is_ordered(tmp_path: Path) -> None:
    """No later row appears before an earlier row in the three partitions."""
    data_directory = tmp_path / "data"
    write_dataset(
        generate_dataset(customers=200, end_date=dt.date(2026, 10, 1)),
        data_directory,
    )
    features = pd.read_parquet(data_directory / "features.parquet")
    labels = pd.read_parquet(data_directory / "labels.parquet")
    splits = temporal_split(
        features.merge(labels, on=[ENTITY_COLUMN, TIMESTAMP_COLUMN])
    )

    assert len(splits.train) == 560
    assert len(splits.validation) == 120
    assert len(splits.test) == 120
    assert (
        splits.train["event_timestamp"].max()
        <= splits.validation["event_timestamp"].min()
    )
    assert (
        splits.validation["event_timestamp"].max()
        <= splits.test["event_timestamp"].min()
    )


def test_build_entity_frame_projects_join_keys(tmp_path: Path) -> None:
    """The Feast entity frame carries one ordered row per labeled event."""
    data_directory = tmp_path / "data"
    write_dataset(
        generate_dataset(customers=200, end_date=dt.date(2026, 10, 1)),
        data_directory,
    )
    labels = pd.read_parquet(data_directory / "labels.parquet")

    entity_df = build_entity_frame(labels)

    assert list(entity_df.columns) == [ENTITY_COLUMN, TIMESTAMP_COLUMN]
    assert len(entity_df) == len(labels)
    assert entity_df[TIMESTAMP_COLUMN].is_monotonic_increasing
