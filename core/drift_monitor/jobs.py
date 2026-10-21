"""Kubernetes retrain-job control and model score metrics."""

from __future__ import annotations

import json
import logging
import time
from typing import TYPE_CHECKING

from mlp_common.drift import DriftReport

if TYPE_CHECKING:
    from drift_monitor.main import DriftMetrics, MonitorSettings

LOGGER = logging.getLogger(__name__)


def job_terminal(
    *, active: int | None, failed: int | None, completion_time: object
) -> bool:
    """Return whether a retrain Job has succeeded or exhausted retries."""
    if completion_time is not None:
        return True
    return (failed or 0) > 0 and not (active or 0)


def retrain_in_flight(namespace: str) -> bool:
    """Return whether any retrain Job is not in a terminal state."""
    from kubernetes import client as k8s_client
    from kubernetes import config as k8s_config

    try:
        k8s_config.load_incluster_config()
    except Exception:
        k8s_config.load_kube_config()
    jobs = k8s_client.BatchV1Api().list_namespaced_job(
        namespace=namespace, label_selector="app=retrain"
    )
    return any(
        not job_terminal(
            active=job.status.active,
            failed=job.status.failed,
            completion_time=job.status.completion_time,
        )
        for job in jobs.items
    )


def create_retrain_job(
    *, champion_version: str, drift_report: DriftReport, settings: MonitorSettings
) -> str:
    """Create a retrain Job from the chart-owned template ConfigMap."""
    from kubernetes import client as k8s_client
    from kubernetes import config as k8s_config

    try:
        k8s_config.load_incluster_config()
    except Exception:
        k8s_config.load_kube_config()
    core = k8s_client.CoreV1Api()
    template = core.read_namespaced_config_map(
        settings.template_configmap, settings.jobs_namespace
    )
    pod_spec = json.loads(template.data["pod-spec.json"])
    name = f"retrain-{champion_version}-{int(time.time())}"
    pod_spec["containers"][0]["env"].extend(
        [
            {"name": "PARENT_CHAMPION", "value": champion_version},
            {
                "name": "DRIFT_REPORT",
                "value": json.dumps(
                    {
                        "drifted_features": drift_report.drifted_features,
                        "features": [
                            {
                                "feature": item.feature,
                                "psi": item.psi,
                                "ks_d": item.ks_d,
                                "ks_p": item.ks_p,
                            }
                            for item in drift_report.features
                        ],
                    }
                ),
            },
        ]
    )
    job = {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {
            "name": name,
            "namespace": settings.jobs_namespace,
            "labels": {"app": "retrain"},
        },
        "spec": {
            "ttlSecondsAfterFinished": 3600,
            "backoffLimit": 1,
            "template": {
                "metadata": {"labels": {"app": "retrain"}},
                "spec": pod_spec,
            },
        },
    }
    k8s_client.BatchV1Api().create_namespaced_job(settings.jobs_namespace, job)
    LOGGER.info("retrain job created", extra={"job": name})
    return name


def update_auc_gauges(tracking_uri: str, metrics: DriftMetrics) -> None:
    """Export champion and candidate test AUC for the health dashboard."""
    try:
        from mlflow.tracking import MlflowClient

        client = MlflowClient(tracking_uri)
        for alias, gauge in (("champion", metrics.champion_auc),):
            try:
                meta = client.get_model_version_by_alias("loan-default", alias)
                run = client.get_run(meta.run_id or "")
                gauge.set(run.data.metrics.get("test_auc", 0.0))
            except Exception:
                gauge.set(0.0)
        try:
            candidate = client.get_model_version_by_alias("loan-default", "candidate")
            run = client.get_run(candidate.run_id or "")
            metrics.candidate_auc.set(run.data.metrics.get("test_auc", 0.0))
        except Exception:
            metrics.candidate_auc.set(0.0)
    except Exception:
        LOGGER.warning("auc gauge update failed", exc_info=True)
