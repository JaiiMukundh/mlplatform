"""Restore the repeatable demo baseline (P8.7, SPEC 6.4).

Regenerates the deterministic baseline data, republishes it, fully
rematerializes the online store (timestamps move backwards, so incremental
materialization would write nothing), repoints the champion alias at the
baseline version, redeploys it, truncates prediction_log, and clears drift
state. SPEC names v1 as the baseline version; v2 superseded it with
bit-identical weights (P7.4 drill a), so the baseline version defaults to 2.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import urllib.request
from pathlib import Path

BASELINE_VERSION = "4"


def _mlflow(path: str, method: str = "GET", payload: bytes | None = None) -> bytes:
    """Call the MLflow tracking server from the host (registry APIs only)."""
    request = urllib.request.Request(
        f"http://localhost:5000{path}",
        data=payload,
        headers={"content-type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def _has_alias(alias: str) -> bool:
    """Return whether the registry currently binds one alias."""
    payload = _mlflow("/api/2.0/mlflow/registered-models/get?name=loan-default")
    aliases = json.loads(payload)["registered_model"].get("aliases", [])
    return any(item["alias"] == alias for item in aliases)


def _model_data_end(version: str) -> dt.date:
    """Read the baseline run's data end so reset data matches its reference."""
    model = json.loads(
        _mlflow(
            f"/api/2.0/mlflow/model-versions/get?name=loan-default&version={version}"
        )
    )["model_version"]
    run = json.loads(_mlflow(f"/api/2.0/mlflow/runs/get?run_id={model['run_id']}"))[
        "run"
    ]
    params = {item["key"]: item["value"] for item in run["data"]["params"]}
    data_end = params.get("data_end")
    if not data_end:
        raise ValueError(f"baseline version {version} has no data_end parameter")
    return dt.date.fromisoformat(data_end[:10])


def parse_args() -> argparse.Namespace:
    """Parse reset CLI options."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=BASELINE_VERSION)
    return parser.parse_args()


def _recover_pending_staging_release() -> None:
    """Roll staging back to its last deployed revision after an interruption."""
    status = subprocess.run(
        ["helm", "status", "model-api-staging", "-n", "staging"],
        check=False,
        capture_output=True,
        text=True,
    )
    if "pending-" not in status.stdout:
        return
    history = subprocess.run(
        ["helm", "history", "model-api-staging", "-n", "staging", "-o", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    revisions = [
        item["revision"]
        for item in json.loads(history.stdout)
        if item["status"] == "deployed"
    ]
    if not revisions:
        raise RuntimeError("staging release is pending and has no deployed revision")
    revision = max(revisions)
    subprocess.run(
        [
            "helm",
            "rollback",
            "model-api-staging",
            str(revision),
            "-n",
            "staging",
            "--wait",
            "--timeout",
            "5m",
        ],
        check=True,
    )


def main() -> int:
    """Rebuild the baseline and redeploy the baseline champion."""
    args = parse_args()
    end_date = _model_data_end(args.version)
    _recover_pending_staging_release()

    subprocess.run(
        [
            "uv",
            "run",
            "python",
            "-m",
            "ml.data.generate",
            "--out",
            "data",
            "--seed",
            "42",
            "--end-date",
            end_date.isoformat(),
        ],
        check=True,
    )
    repo_root = Path(__file__).resolve().parents[2]
    publish_sh = (
        repo_root / "ops" / "scripts" / "publish_feast_data.sh"
        if (repo_root / "ops" / "scripts" / "publish_feast_data.sh").exists()
        else Path("scripts/publish_feast_data.sh")
    )
    run_job_sh = (
        repo_root / "ops" / "scripts" / "run_job.sh"
        if (repo_root / "ops" / "scripts" / "run_job.sh").exists()
        else Path("scripts/run_job.sh")
    )
    remat_cand = repo_root / "infra" / "deploy" / "feast" / "rematerialize-job.yaml"
    remat_yaml = (
        remat_cand
        if remat_cand.exists()
        else Path("deploy/feast/rematerialize-job.yaml")
    )
    deploy_sh = (
        repo_root / "ops" / "scripts" / "deploy.sh"
        if (repo_root / "ops" / "scripts" / "deploy.sh").exists()
        else Path("scripts/deploy.sh")
    )

    subprocess.run(["bash", str(publish_sh)], check=True)
    # Feast's full rematerialization does not overwrite Redis keys whose
    # timestamps are newer than the reset snapshot.  Flush the demo-only
    # ephemeral online store so no drifted values survive the reset.
    subprocess.run(
        [
            "kubectl",
            "-n",
            "data",
            "exec",
            "deploy/redis",
            "--",
            "redis-cli",
            "FLUSHALL",
        ],
        check=True,
    )
    subprocess.run(
        ["bash", str(run_job_sh), str(remat_yaml)],
        check=True,
    )

    _mlflow(
        "/api/2.0/mlflow/registered-models/alias",
        method="POST",
        payload=(
            f'{{"name":"loan-default","alias":"champion","version":"{args.version}"}}'
        ).encode(),
    )
    _mlflow(
        "/api/2.0/mlflow/registered-models/alias",
        method="DELETE",
        payload=b'{"name":"loan-default","alias":"candidate"}',
    ) if _has_alias("candidate") else None
    subprocess.run(
        [
            "bash",
            str(deploy_sh),
            "model-api",
            "serving",
            "dev",
            "--set",
            f"model.version={args.version}",
        ],
        check=True,
    )
    subprocess.run(
        [
            "kubectl",
            "-n",
            "data",
            "delete",
            "job",
            "-l",
            "app=retrain",
            "--ignore-not-found",
            "--wait=true",
        ],
        check=True,
    )
    subprocess.run(
        [
            "kubectl",
            "-n",
            "data",
            "exec",
            "postgres-0",
            "--",
            "psql",
            "-U",
            "mlp",
            "-d",
            "mlp",
            "-c",
            "TRUNCATE prediction_log; DELETE FROM drift_state; DELETE FROM drift_meta;",
        ],
        check=True,
    )
    subprocess.run(
        [
            "kubectl",
            "-n",
            "observability",
            "rollout",
            "restart",
            "deployment/drift-monitor",
        ],
        check=True,
    )
    subprocess.run(
        [
            "kubectl",
            "-n",
            "observability",
            "rollout",
            "status",
            "deployment/drift-monitor",
            "--timeout=120s",
        ],
        check=True,
    )
    print(
        f"reset_demo complete: baseline data through {end_date}, "
        f"champion v{args.version}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
