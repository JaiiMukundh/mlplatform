"""Simulate drift scenarios for the self-healing demo (P8.7, SPEC 6.4).

Scenarios: ``covariate`` (shifted feature distributions), ``concept`` (new
label mechanism), ``both`` (default demo: shifted features + new mechanism).

The script appends one new snapshot for every customer, uploads both Parquet
files to MinIO, and runs incremental materialization so the online store and
subsequent prediction traffic carry the drift. The champion-AUC-drop
assertion (SPEC: >= 0.07 on new data) uses the local file model, whose
weights are bit-identical to the registered champion (proven in P6.7), and
applies to scenarios with a concept change.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from ml.data.generate import _calibrate_intercept, _generate_labels
from ml.data.schemas import (
    ENTITY_COLUMN,
    FEATURE_COLUMNS,
    LABEL_COLUMN,
    TIMESTAMP_COLUMN,
    validate_features,
    validate_labels,
)
from ml.evaluate import evaluate_binary_classifier
from mlp_common.schemas import MODEL_FEATURES

DATA_DIR = Path("data")
TARGET_POSITIVE_RATE = 0.12

#: Concept-drift mechanism: the debt_to_income effect flips sign, credit and
#: late-payment effects weaken, utilization strengthens (baseline was
#: [-0.70, 1.00, -0.55, 0.85, -0.45, 0.80]). Drops the champion by ~0.18 AUC.
CONCEPT_WEIGHTS = np.array([-0.70, -0.50, 0.10, 0.50, -0.45, 1.20])


def shifted_snapshot(latest: pd.DataFrame, timestamp: pd.Timestamp) -> pd.DataFrame:
    """Copy the latest snapshot and apply the SPEC covariate shifts."""
    rng = np.random.default_rng(7)
    frame = latest.copy()
    frame[TIMESTAMP_COLUMN] = timestamp
    frame["income"] = frame["income"] * 0.75
    frame["debt_to_income"] = (frame["debt_to_income"] + 0.15).clip(upper=1.0)
    frame["num_late_payments_90d"] = rng.poisson(lam=1.4, size=len(frame)).astype(
        "int64"
    )
    frame["utilization_ratio"] = (frame["utilization_ratio"] + 0.15).clip(upper=1.0)
    return frame[[ENTITY_COLUMN, TIMESTAMP_COLUMN, *FEATURE_COLUMNS]]


def concept_labels(features: pd.DataFrame, *, seed: int = 11) -> pd.DataFrame:
    """Generate labels for new rows under the drifted concept."""
    rng = np.random.default_rng(seed)
    matrix = features[FEATURE_COLUMNS].to_numpy(dtype="float64")
    standardized = (matrix - matrix.mean(axis=0)) / matrix.std(axis=0)
    noise = rng.normal(loc=0.0, scale=0.5, size=len(features))
    signal = standardized @ CONCEPT_WEIGHTS + noise
    intercept = _calibrate_intercept(signal, TARGET_POSITIVE_RATE)
    probabilities = 1.0 / (1.0 + np.exp(-(signal + intercept)))
    outcomes = rng.binomial(1, probabilities).astype("int8")
    return features[[ENTITY_COLUMN, TIMESTAMP_COLUMN]].assign(
        **{LABEL_COLUMN: outcomes}
    )


def parse_args() -> argparse.Namespace:
    """Parse simulation CLI options."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scenario", choices=["covariate", "concept", "both"], default="both"
    )
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR)
    return parser.parse_args()


def main() -> int:
    """Append the drifted snapshot, publish it, and materialize it."""
    args = parse_args()
    features = pd.read_parquet(args.data_dir / "features.parquet")
    labels = pd.read_parquet(args.data_dir / "labels.parquet")
    latest = pd.read_parquet(args.data_dir / "features_latest.parquet")

    # Incremental materialization only covers (cursor, now]: a future-dated
    # snapshot would never reach the online store, so cap the new timestamp
    # at the current time (weekly cadence when the data is stale).
    max_timestamp = pd.Timestamp(features[TIMESTAMP_COLUMN].max())
    now = pd.Timestamp.now(tz="UTC")
    new_timestamp = min(max_timestamp + pd.Timedelta(days=7), now)
    if new_timestamp <= max_timestamp:
        print("ERROR: clock did not advance past the data window")
        return 1
    if args.scenario == "concept":
        new_features = latest.copy()
        new_features[TIMESTAMP_COLUMN] = new_timestamp
    else:
        new_features = shifted_snapshot(latest, new_timestamp)
    if args.scenario == "covariate":
        # Same concept on shifted features: reuse the baseline mechanism.
        new_labels = _generate_labels(np.random.default_rng(21), new_features)
    else:
        new_labels = concept_labels(new_features)
    validate_features(new_features)
    validate_labels(new_labels)

    updated_features = pd.concat([features, new_features], ignore_index=True)
    updated_labels = pd.concat([labels, new_labels], ignore_index=True)
    updated_features.to_parquet(args.data_dir / "features.parquet", index=False)
    updated_labels.to_parquet(args.data_dir / "labels.parquet", index=False)
    new_features.to_parquet(args.data_dir / "features_latest.parquet", index=False)
    print(
        f"simulate_drift scenario={args.scenario} "
        f"new_timestamp={new_timestamp.date()} rows={len(new_features)}"
    )

    model = joblib.load("artifacts/model.joblib")
    baseline = labels.loc[labels[TIMESTAMP_COLUMN] == labels[TIMESTAMP_COLUMN].max()]
    baseline_features = features.merge(
        baseline[[ENTITY_COLUMN, TIMESTAMP_COLUMN]],
        on=[ENTITY_COLUMN, TIMESTAMP_COLUMN],
    )
    baseline_auc = evaluate_binary_classifier(
        model, baseline_features[MODEL_FEATURES], baseline[LABEL_COLUMN]
    )["auc"]
    new_auc = evaluate_binary_classifier(
        model, new_features[MODEL_FEATURES], new_labels[LABEL_COLUMN]
    )["auc"]
    drop = baseline_auc - new_auc
    print(
        f"champion baseline_auc={baseline_auc:.4f} "
        f"new_data_auc={new_auc:.4f} drop={drop:.4f}"
    )
    if args.scenario in ("concept", "both") and drop < 0.07:
        print("ERROR: concept drift must drop champion AUC by >= 0.07")
        return 1

    subprocess.run(["bash", "scripts/publish_feast_data.sh"], check=True)
    subprocess.run(
        ["bash", "scripts/run_job.sh", "deploy/feast/materialize-job.yaml"],
        check=True,
    )
    print("simulate_drift published + materialized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
