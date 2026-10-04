"""Generate deterministic, controllably drifting loan-default data."""

from __future__ import annotations

import argparse
import datetime as dt
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd

from ml.data.schemas import (
    ENTITY_COLUMN,
    FEATURE_COLUMNS,
    LABEL_COLUMN,
    TIMESTAMP_COLUMN,
    validate_features,
    validate_labels,
)

DEFAULT_CUSTOMERS = 20_000
DEFAULT_SNAPSHOTS = 4
TARGET_POSITIVE_RATE = 0.12


@dataclass(frozen=True)
class GeneratedData:
    """Feature, label, and latest-feature frames written by the CLI."""

    features: pd.DataFrame
    labels: pd.DataFrame
    latest_features: pd.DataFrame


def _snapshot(rng: np.random.Generator, customer_ids: np.ndarray) -> pd.DataFrame:
    """Draw one baseline snapshot from the distributions in the specification."""
    size = len(customer_ids)
    return pd.DataFrame(
        {
            ENTITY_COLUMN: customer_ids,
            "income": rng.lognormal(mean=10.8, sigma=0.5, size=size),
            "debt_to_income": rng.beta(2.0, 5.0, size=size),
            "credit_history_months": np.clip(
                rng.gamma(shape=4.0, scale=30.0, size=size), 6.0, 480.0
            ),
            "num_late_payments_90d": rng.poisson(lam=0.6, size=size).astype(
                "int64"
            ),
            "avg_monthly_balance": rng.lognormal(mean=8.0, sigma=0.8, size=size),
            "utilization_ratio": rng.beta(2.0, 3.0, size=size),
        }
    )


def _calibrate_intercept(signal: np.ndarray, target: float) -> float:
    """Find the logistic intercept whose expected positive rate is ``target``."""
    low, high = -12.0, 12.0
    for _ in range(80):
        midpoint = (low + high) / 2.0
        mean_probability = np.mean(1.0 / (1.0 + np.exp(-(signal + midpoint))))
        if mean_probability < target:
            low = midpoint
        else:
            high = midpoint
    return (low + high) / 2.0


def _generate_labels(
    rng: np.random.Generator, features: pd.DataFrame
) -> pd.DataFrame:
    """Generate binary outcomes from the documented directional risk mechanism."""
    matrix = features[FEATURE_COLUMNS].to_numpy(dtype="float64")
    standardized = (matrix - matrix.mean(axis=0)) / matrix.std(axis=0)
    weights = np.array([-0.70, 1.00, -0.55, 0.85, -0.45, 0.80])
    noise = rng.normal(loc=0.0, scale=0.5, size=len(features))
    signal = standardized @ weights + noise
    intercept = _calibrate_intercept(signal, TARGET_POSITIVE_RATE)
    probabilities = 1.0 / (1.0 + np.exp(-(signal + intercept)))
    outcomes = rng.binomial(1, probabilities).astype("int8")
    return features[[ENTITY_COLUMN, TIMESTAMP_COLUMN]].assign(
        **{LABEL_COLUMN: outcomes}
    )


def generate_dataset(
    *,
    seed: int = 42,
    customers: int = DEFAULT_CUSTOMERS,
    snapshots: int = DEFAULT_SNAPSHOTS,
    end_date: dt.date | None = None,
) -> GeneratedData:
    """Generate all snapshots, labels, and the latest serving feature view."""
    if customers < 1 or snapshots < 1:
        raise ValueError("customers and snapshots must both be positive")

    effective_end = end_date or (dt.datetime.now(dt.UTC).date() - dt.timedelta(days=1))
    customer_ids = np.arange(customers, dtype="int64")
    rng = np.random.default_rng(seed)
    frames: list[pd.DataFrame] = []

    for weeks_ago in reversed(range(snapshots)):
        frame = _snapshot(rng, customer_ids)
        timestamp = effective_end - dt.timedelta(days=7 * weeks_ago)
        frame.insert(1, TIMESTAMP_COLUMN, pd.Timestamp(timestamp, tz="UTC"))
        frames.append(frame)

    features = pd.concat(frames, ignore_index=True)
    features = features[[ENTITY_COLUMN, TIMESTAMP_COLUMN, *FEATURE_COLUMNS]]
    labels = _generate_labels(rng, features)
    latest = features.loc[
        features[TIMESTAMP_COLUMN] == features[TIMESTAMP_COLUMN].max()
    ].reset_index(drop=True)

    validate_features(features)
    validate_features(latest)
    validate_labels(labels)
    return GeneratedData(features=features, labels=labels, latest_features=latest)


def write_dataset(dataset: GeneratedData, output_directory: Path) -> None:
    """Write the generated frames atomically enough for repeatable local use."""
    output_directory.mkdir(parents=True, exist_ok=True)
    dataset.features.to_parquet(output_directory / "features.parquet", index=False)
    dataset.labels.to_parquet(output_directory / "labels.parquet", index=False)
    dataset.latest_features.to_parquet(
        output_directory / "features_latest.parquet", index=False
    )


def parse_args() -> argparse.Namespace:
    """Parse command-line options for the data generator."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=Path("data"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--end-date",
        type=dt.date.fromisoformat,
        default=None,
        help="UTC date for the latest snapshot (default: yesterday)",
    )
    return parser.parse_args()


def main() -> None:
    """Generate and report the three local Parquet assets."""
    args = parse_args()
    dataset = generate_dataset(seed=args.seed, end_date=args.end_date)
    write_dataset(dataset, args.out)
    positive_rate = dataset.labels[LABEL_COLUMN].mean()
    print(
        f"generated rows={len(dataset.features)} customers="
        f"{dataset.features[ENTITY_COLUMN].nunique()} "
        f"positive_rate={positive_rate:.4f} out={args.out}"
    )


if __name__ == "__main__":
    main()
