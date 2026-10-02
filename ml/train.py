"""Train the reproducible file-backed model; MLflow mode arrives in P6."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import joblib
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier

from ml.data.schemas import (
    ENTITY_COLUMN,
    FEATURE_COLUMNS,
    LABEL_COLUMN,
    TIMESTAMP_COLUMN,
)
from ml.evaluate import evaluate_binary_classifier


@dataclass(frozen=True)
class TemporalSplits:
    """Chronologically ordered train, validation, and test partitions."""

    train: pd.DataFrame
    validation: pd.DataFrame
    test: pd.DataFrame


def load_training_frame(data_directory: Path) -> pd.DataFrame:
    """Join generated features to labels using both entity and event timestamp."""
    features = pd.read_parquet(data_directory / "features.parquet")
    labels = pd.read_parquet(data_directory / "labels.parquet")
    frame = features.merge(
        labels,
        on=[ENTITY_COLUMN, TIMESTAMP_COLUMN],
        how="inner",
        validate="one_to_one",
    )
    if len(frame) != len(features) or len(frame) != len(labels):
        raise ValueError("feature/label join dropped rows")
    return frame.sort_values([TIMESTAMP_COLUMN, ENTITY_COLUMN]).reset_index(drop=True)


def temporal_split(frame: pd.DataFrame) -> TemporalSplits:
    """Split sorted observations 70%/15%/15% without shuffling future into past."""
    if len(frame) < 20:
        raise ValueError("at least 20 rows are required for a temporal split")
    ordered = frame.sort_values([TIMESTAMP_COLUMN, ENTITY_COLUMN]).reset_index(
        drop=True
    )
    train_end = int(len(ordered) * 0.70)
    validation_end = int(len(ordered) * 0.85)
    return TemporalSplits(
        train=ordered.iloc[:train_end].copy(),
        validation=ordered.iloc[train_end:validation_end].copy(),
        test=ordered.iloc[validation_end:].copy(),
    )


def build_model() -> HistGradientBoostingClassifier:
    """Create the pinned deterministic gradient-boosted classifier."""
    return HistGradientBoostingClassifier(
        learning_rate=0.08,
        max_iter=180,
        max_leaf_nodes=31,
        l2_regularization=0.2,
        random_state=42,
    )


def _feature_schema(frame: pd.DataFrame) -> dict[str, Any]:
    """Build the serving schema artifact in canonical feature order."""
    return {
        "features": [
            {"name": column, "dtype": str(frame[column].dtype)}
            for column in FEATURE_COLUMNS
        ],
        "entity": ENTITY_COLUMN,
        "timestamp": TIMESTAMP_COLUMN,
        "label": LABEL_COLUMN,
    }


def train_file_model(data_directory: Path, artifacts_directory: Path) -> dict[str, Any]:
    """Train, evaluate, and persist the complete P1 artifact set."""
    frame = load_training_frame(data_directory)
    splits = temporal_split(frame)
    model = build_model()
    model.fit(splits.train[FEATURE_COLUMNS], splits.train[LABEL_COLUMN])

    metrics: dict[str, Any] = {
        "validation": evaluate_binary_classifier(
            model,
            splits.validation[FEATURE_COLUMNS],
            splits.validation[LABEL_COLUMN],
        ),
        "test": evaluate_binary_classifier(
            model, splits.test[FEATURE_COLUMNS], splits.test[LABEL_COLUMN]
        ),
        "rows": {
            "train": len(splits.train),
            "validation": len(splits.validation),
            "test": len(splits.test),
        },
    }

    artifacts_directory.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, artifacts_directory / "model.joblib")
    (artifacts_directory / "metrics.json").write_text(
        json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    reference = splits.train[FEATURE_COLUMNS].sample(
        n=min(10_000, len(splits.train)), random_state=42
    )
    reference.to_parquet(artifacts_directory / "reference.parquet", index=False)
    (artifacts_directory / "feature_schema.json").write_text(
        json.dumps(_feature_schema(frame), indent=2) + "\n", encoding="utf-8"
    )
    return metrics


def parse_args() -> argparse.Namespace:
    """Parse training CLI options."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["file", "mlflow"], default="file")
    parser.add_argument("--data-dir", type=Path, default=Path("data"))
    parser.add_argument("--artifacts-dir", type=Path, default=Path("artifacts"))
    return parser.parse_args()


def main() -> None:
    """Run the selected training mode and print its acceptance metrics."""
    args = parse_args()
    if args.mode != "file":
        raise NotImplementedError("MLflow training mode is implemented in P6.4")
    metrics = train_file_model(args.data_dir, args.artifacts_dir)
    print(
        f"trained rows={metrics['rows']} "
        f"validation_auc={metrics['validation']['auc']:.4f} "
        f"test_auc={metrics['test']['auc']:.4f}"
    )


if __name__ == "__main__":
    main()
