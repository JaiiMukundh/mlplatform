"""Cloud migration regressions that run without Azure credentials or a cluster."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest
import yaml
from retrain.dispatch import dispatch_candidate

ROOT = Path(__file__).resolve().parents[1]


def check(action: str, **overrides: str) -> subprocess.CompletedProcess[str]:
    """Run the configuration gate only; never initialize or mutate Azure."""
    environment = {
        **os.environ,
        "ARM_CLIENT_ID": "test-client",
        "ARM_TENANT_ID": "test-tenant",
        "ARM_SUBSCRIPTION_ID": "test-subscription",
        "TF_STATE_ACCOUNT": "teststate",
        "TF_VAR_kubernetes_version": "1.36.4",
        "TF_VAR_budget_email": "owner@example.com",
        "ACTION": action,
        "CONFIRMATION": "",
        **overrides,
    }
    return subprocess.run(
        ["bash", "ops/scripts/azure.sh", "check"],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize("action", ["deploy", "wake", "destroy"])
def test_billable_actions_require_explicit_confirmation(action: str) -> None:
    """Cloud configuration cannot pass accidentally without the human's choice."""
    result = check(action)
    assert result.returncode != 0
    assert f"confirmation must be {action.upper()}" in result.stderr
    assert check(action, CONFIRMATION=action.upper()).returncode == 0


def test_plan_needs_configuration_but_no_billing_confirmation() -> None:
    """Plan works without approval, while absent identity/state fails before login."""
    assert check("plan").returncode == 0
    result = check("plan", TF_STATE_ACCOUNT="")
    assert result.returncode != 0
    assert "TF_STATE_ACCOUNT" in result.stderr


def test_release_rejects_shell_payloads() -> None:
    """Candidate identifiers cannot become executable shell syntax in a Job."""
    assert check("release", VERSION="7").returncode == 0
    assert check("release", VERSION="7; touch /tmp/cloud-payload").returncode != 0


def test_make_cloud_training_requires_an_explicit_cloud_image() -> None:
    """Make must preserve the shell guard instead of erasing it as a Make variable."""
    environment = dict(os.environ)
    environment.pop("TRAINING_IMAGE", None)
    result = subprocess.run(
        ["make", "train-azure"],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert "set TRAINING_IMAGE to the deployed ACR" in result.stderr


def test_cloud_retrain_keeps_acr_images_and_immutable_tag() -> None:
    """The in-cluster release must reuse the deployed cloud images at every step."""
    output = subprocess.run(
        [
            "helm",
            "template",
            "retrain",
            "infra/deploy/charts/retrain",
            "--set",
            "image.repository=demo.azurecr.io/mlp-retrain,image.tag=abc123",
            "--set",
            "env.MODEL_API_REPOSITORY=demo.azurecr.io/mlp-model-api",
            "--set",
            "env.TRAINING_IMAGE=demo.azurecr.io/mlp-training:abc123",
            "--set",
            "env.IMAGE_TAG=abc123,env.DEPLOY_TARGET=azure",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    config = next(
        doc for doc in yaml.safe_load_all(output) if doc["kind"] == "ConfigMap"
    )
    container = json.loads(config["data"]["pod-spec.json"])["containers"][0]
    assert container["image"] == "demo.azurecr.io/mlp-retrain:abc123"
    environment = {item["name"]: item.get("value") for item in container["env"]}
    assert environment["TRAINING_IMAGE"] == "demo.azurecr.io/mlp-training:abc123"
    assert environment["MODEL_API_REPOSITORY"] == "demo.azurecr.io/mlp-model-api"
    assert environment["IMAGE_TAG"] == "abc123"
    assert environment["DEPLOY_TARGET"] == "azure"


def test_dispatch_forwards_cloud_image_tag(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An Azure retrain release must not fall back to the absent dev image tag."""
    monkeypatch.setenv("IMAGE_TAG", "abc123")
    script = tmp_path / "release.sh"
    result = tmp_path / "result.txt"
    script.write_text('printf "%s\\n" "$1" "$2" > result.txt\n')
    dispatch_candidate("9", release_script=str(script), workdir=str(tmp_path))
    assert result.read_text().splitlines() == ["9", "abc123"]
