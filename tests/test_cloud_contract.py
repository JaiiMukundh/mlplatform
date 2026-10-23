"""Cloud migration regressions that run without Azure credentials or a cluster."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest
from retrain.dispatch import dispatch_candidate

ROOT = Path(__file__).resolve().parents[1]


def test_public_service_exposes_only_configured_port() -> None:
    """Terraform's shared Azure IP uses one external port per Service."""
    manifest = ROOT / "infra/manifests/observability.json.tftpl"
    resources = json.loads(manifest.read_text())
    grafana = next(
        item
        for item in resources.values()
        if item["kind"] == "Service"
        and item["metadata"]["name"] == "kube-prometheus-stack-grafana"
    )
    assert grafana["spec"]["type"] == "LoadBalancer"
    assert [port["port"] for port in grafana["spec"]["ports"]] == [3000]
    assert grafana["spec"]["loadBalancerSourceRanges"] == [
        "${ALLOWED_CIDR}",
        "${RUNNER_CIDR}",
    ]


def test_loki_caches_fit_the_small_aks_node_pool() -> None:
    """Cache sizing must not reserve more RAM than either AKS node can provide."""
    resources = json.loads(
        (ROOT / "infra/manifests/observability.json.tftpl").read_text()
    )
    cache_budgets = {
        "loki-chunks-cache": (128, 192, 256),
        "loki-results-cache": (64, 96, 128),
    }
    for name, (cache_mb, request_mb, limit_mb) in cache_budgets.items():
        workload = next(
            item
            for item in resources.values()
            if item["kind"] == "StatefulSet" and item["metadata"]["name"] == name
        )
        container = workload["spec"]["template"]["spec"]["containers"][0]
        assert container["args"][:2] == ["-m", str(cache_mb)]
        assert container["resources"]["requests"]["memory"] == f"{request_mb}Mi"
        assert container["resources"]["limits"]["memory"] == f"{limit_mb}Mi"


def test_azure_resolves_mlflow_aliases_from_registered_model_search() -> None:
    """Initial deploy must not use a failing direct GET for a fresh MLflow alias."""
    script = (ROOT / "scripts/azure.sh").read_text()
    assert "model_alias_version champion" in script
    assert "model_alias_version baseline" in script
    assert "registered-models/search" in script
    assert "registered-models/alias?name=" not in script


def test_azure_verification_checks_live_model_api_metrics() -> None:
    """Cloud verification must exercise metrics from the deployed API process."""
    script = (ROOT / "scripts/azure.sh").read_text()
    assert '"${api_url}/metrics"' in script
    assert "^http_requests_total" in script
    assert "^model_info{" in script


def test_azure_verify_restores_runner_allowlist_and_uses_port_forwarding() -> None:
    """Cloud checks avoid public ingress while cleaning up runner access."""
    script = (ROOT / "scripts/azure.sh").read_text()
    assert 'if [[ "${ACTION}" == verify || "${ACTION}" == dashboard ]]' in script
    assert "--api-server-authorized-ip-ranges" in script
    assert "trap cleanup_verify EXIT" in script
    assert "port-forward service/model-api 18080:8080" in script
    assert "port-forward service/dashboard 18443:443" in script
    assert "--retry 30 --retry-all-errors --retry-delay 2" in script


def test_github_oidc_session_refreshes_for_long_azure_provisioning(
    tmp_path: Path,
) -> None:
    """A fresh GitHub assertion must renew Azure CLI auth after Terraform apply."""
    binaries = tmp_path / "bin"
    binaries.mkdir()
    fake_curl = binaries / "curl"
    fake_curl.write_text('#!/bin/sh\nprintf \'{"value":"fresh-oidc-token"}\\n\'\n')
    fake_curl.chmod(0o755)
    fake_az = binaries / "az"
    fake_az.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$AZ_CALLS"\n')
    fake_az.chmod(0o755)
    calls = tmp_path / "azure-calls.txt"
    environment = {
        **os.environ,
        "PATH": f"{binaries}:{os.environ['PATH']}",
        "AZ_CALLS": str(calls),
        "ACTIONS_ID_TOKEN_REQUEST_URL": "https://token.actions.test/oidc",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "github-request-token",
        "ARM_CLIENT_ID": "client",
        "ARM_TENANT_ID": "tenant",
        "ARM_SUBSCRIPTION_ID": "subscription",
    }
    result = subprocess.run(
        [
            "bash",
            "-c",
            f'source "{ROOT}/scripts/azure_oidc.sh"; refresh_azure_oidc_login',
        ],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == [
        "login --service-principal --username client --tenant tenant "
        "--federated-token fresh-oidc-token --output none",
        "account set --subscription subscription",
    ]
    assert "refresh_azure_oidc_login" in (ROOT / "scripts/azure.sh").read_text()


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
        "AZURE_ALLOWED_CIDR": "203.0.113.10/32",
        "ACTION": action,
        "CONFIRMATION": "",
        **overrides,
    }
    return subprocess.run(
        ["bash", "scripts/azure.sh", "check"],
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


def test_dashboard_action_keeps_the_terraform_allowlist() -> None:
    """Dashboard verification preserves the Terraform-managed HTTPS Service."""
    assert check("dashboard").returncode == 0
    resources = json.loads((ROOT / "infra/manifests/app.json.tftpl").read_text())
    service = next(
        item
        for item in resources.values()
        if item["kind"] == "Service" and item["metadata"]["name"] == "dashboard"
    )
    deployment = next(
        item
        for item in resources.values()
        if item["kind"] == "Deployment" and item["metadata"]["name"] == "dashboard"
    )
    assert service["spec"]["loadBalancerSourceRanges"] == [
        "${ALLOWED_CIDR}",
        "${RUNNER_CIDR}",
    ]
    assert service["spec"]["externalTrafficPolicy"] == "Local"
    assert service["spec"]["ports"][0]["port"] == 443
    workflow = (ROOT / ".github/workflows/cd.yml").read_text()
    deploy_script = (ROOT / "scripts/azure.sh").read_text()
    assert "inputs.action == 'deploy' || inputs.action == 'dashboard'" in workflow
    assert "https://127.0.0.1:18443/healthz" in deploy_script
    assert "port-forward service/dashboard 18443:443" in deploy_script
    dashboard_container = deployment["spec"]["template"]["spec"]["containers"][0]
    assert dashboard_container["startupProbe"]["failureThreshold"] == 120
    assert "deployment/dashboard --timeout=600s" in deploy_script
    assert "kubectl -n observability describe pods -l app=dashboard" in deploy_script


def test_model_api_ingress_waits_for_azure_rule_updates() -> None:
    """Cilium preserves client CIDR for public traffic from the configured network."""
    resources = json.loads((ROOT / "infra/manifests/app.json.tftpl").read_text())
    service = next(
        item
        for item in resources.values()
        if item["kind"] == "Service" and item["metadata"]["name"] == "model-api"
    )
    assert service["spec"]["externalTrafficPolicy"] == "Local"
    assert service["spec"]["loadBalancerSourceRanges"] == [
        "${ALLOWED_CIDR}",
        "${RUNNER_CIDR}",
    ]
    deploy_script = (ROOT / "scripts/azure.sh").read_text()
    assert '"${api_url}/readyz"' in deploy_script
    assert "port-forward service/model-api 18080:8080" in deploy_script


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
    """The in-cluster release uses the deployed ACR image and immutable tag."""
    resources = json.loads((ROOT / "infra/manifests/app.json.tftpl").read_text())
    config = next(
        item
        for item in resources.values()
        if item["kind"] == "ConfigMap"
        and item["metadata"]["name"] == "retrain-job-template"
    )
    container = json.loads(config["data"]["pod-spec.json"])["containers"][0]
    assert container["image"] == "${ACR}/mlp-retrain:${TAG}"
    environment = {item["name"]: item.get("value") for item in container["env"]}
    assert environment["TRAINING_IMAGE"] == "${ACR}/mlp-training:${TAG}"
    assert environment["MODEL_API_REPOSITORY"] == "${ACR}/mlp-model-api"
    assert environment["IMAGE_TAG"] == "${TAG}"
    assert environment["DEPLOY_TARGET"] == "azure"


def test_model_release_updates_the_terraform_deployment(tmp_path: Path) -> None:
    """A model release rolls the existing AKS deployment to an explicit version."""
    kubectl = tmp_path / "kubectl"
    kubectl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$KUBECTL_CALLS"\n')
    kubectl.chmod(0o755)
    calls = tmp_path / "calls.txt"
    result = subprocess.run(
        ["bash", "scripts/deploy.sh", "model-api", "serving", "abc123", "9"],
        cwd=ROOT,
        env={
            **os.environ,
            "PATH": f"{tmp_path}:{os.environ['PATH']}",
            "KUBECTL_CALLS": str(calls),
            "DEPLOY_TARGET": "azure",
            "MODEL_API_REPOSITORY": "demo.azurecr.io/mlp-model-api",
            "SKIP_SMOKE": "1",
        },
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert calls.read_text().splitlines() == [
        "-n serving get deployment model-api",
        "-n serving set image deployment/model-api "
        "api=demo.azurecr.io/mlp-model-api:abc123",
        "-n serving set env deployment/model-api MODEL_VERSION=9",
        "-n serving rollout status deployment/model-api --timeout=5m",
    ]


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


def test_dashboard_serves_page_and_runs_commands_from_repository(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Moving the UI must preserve its template and command working directory."""
    from fastapi.testclient import TestClient

    from ui.app import ACTION_COMMANDS, app

    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("DASHBOARD_PASSWORD", "cloud-test-password")
    monkeypatch.setitem(ACTION_COMMANDS, "verify-layout", "make help")
    with TestClient(app) as client:
        page = client.get("/", auth=("admin", "cloud-test-password"))
        assert page.status_code == 200
        assert "<html" in page.text.lower()
        assert "executeAction('simulate_drift')" in page.text
        assert "await fetch('/api/action'" in page.text
        assert (
            "new EventSource(`/api/stream/${encodeURIComponent(executionId)}`)"
            in page.text
        )
        action = client.post(
            "/api/action",
            json={"action": "verify-layout"},
            auth=("admin", "cloud-test-password"),
        )
        assert action.status_code == 200
        execution_id = action.json()["execution_id"]
        output = client.get(
            f"/api/stream/{execution_id}", auth=("admin", "cloud-test-password")
        )
        assert "MLPlatform targets:" in output.text
        assert "COMPLETED SUCCESSFULLY (EXIT 0)" in output.text


@pytest.mark.parametrize(
    "scenario",
    [
        "normal",
        "partial",
        "unowned",
        "delete_failure",
        "budget_delete_failure",
        "list_failure",
        "expired",
        "not_expired",
        "bad_expiry",
        "orphaned_nodes",
        "startup_unowned",
    ],
)
def test_full_kill_is_state_independent_and_checks_ownership(
    scenario: str, tmp_path: Path
) -> None:
    """Exercise real kill control flow against a fake Azure CLI, never Azure."""
    state = tmp_path / "groups.json"
    owner = "JaiiMukundh/mlplatform"
    groups = {
        "test-app": {"repository": owner},
        "test-state": {"repository": owner},
        "test-nodes": {
            "managedBy": "/subscriptions/test-sub/resourceGroups/test-app/"
            "providers/Microsoft.ContainerService/managedClusters/test-cluster"
        },
    }
    if scenario == "partial":
        groups.pop("test-app")
    if scenario == "orphaned_nodes":
        groups.pop("test-app")
        groups.pop("test-state")
    if scenario in {"unowned", "startup_unowned"}:
        groups["test-state"] = {"repository": "another/repository"}
    for group in groups.values():
        group["deadline"] = (
            "3000-01-01T00:00:00Z"
            if scenario == "not_expired"
            else "invalid"
            if scenario == "bad_expiry"
            else "2000-01-01T00:00:00Z"
        )
    state.write_text(
        json.dumps(
            {
                "groups": groups,
                "deleted": [],
                "budget": {
                    "id": "/subscriptions/test-sub/resourceGroups/test-app/"
                    "providers/Microsoft.Consumption/budgets/mlp-test-monthly"
                },
            }
        )
    )
    cli = tmp_path / "az"
    cli.write_text(
        "#!/usr/bin/env python3\n"
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "path = Path(os.environ['FAKE_AZ_STATE'])\n"
        "state = json.loads(path.read_text())\n"
        "args = sys.argv[1:]\n"
        "if args[:2] == ['account', 'set']:\n"
        "    sys.exit(0)\n"
        "if args[:2] == ['aks', 'list']:\n"
        "    if os.environ['SCENARIO'] == 'list_failure': sys.exit(3)\n"
        "    print('test-nodes'); sys.exit(0)\n"
        "if args[:3] == ['consumption', 'budget', 'show']:\n"
        "    print((state.get('budget') or {}).get('id', '')); sys.exit(0)\n"
        "if args[:3] == ['consumption', 'budget', 'delete']:\n"
        "    if os.environ['SCENARIO'] == 'budget_delete_failure': sys.exit(6)\n"
        "    state['budget'] = None; path.write_text(json.dumps(state)); sys.exit(0)\n"
        "group = args[args.index('--name') + 1]\n"
        "if args[:2] == ['group', 'exists']:\n"
        "    print(str(group in state['groups']).lower())\n"
        "elif args[:2] == ['group', 'show']:\n"
        "    if 'tags.ExpiresAt' in args: print(state['groups'][group]['deadline'])\n"
        "    elif 'tags.Repository' in args:\n"
        "        print(state['groups'][group].get('repository',''))\n"
        "    else: print(json.dumps(state['groups'][group]))\n"
        "elif args[:2] == ['group', 'delete']:\n"
        "    if os.environ['SCENARIO'] == 'delete_failure': sys.exit(4)\n"
        "    state['deleted'].append(group)\n"
        "    del state['groups'][group]\n"
        "    path.write_text(json.dumps(state))\n"
        "else: sys.exit(5)\n"
    )
    cli.chmod(0o755)
    gh = tmp_path / "gh"
    gh.write_text("#!/bin/sh\nexit 0\n")
    gh.chmod(0o755)
    terraform = tmp_path / "terraform"
    terraform.write_text("#!/bin/sh\nexit 95\n")
    terraform.chmod(0o755)
    environment = {
        **os.environ,
        "PATH": f"{tmp_path}:{os.environ['PATH']}",
        "ARM_SUBSCRIPTION_ID": "test-sub",
        "AZURE_RESOURCE_GROUP": "test-app",
        "AZURE_NODE_RESOURCE_GROUP": "test-nodes",
        "TF_STATE_RESOURCE_GROUP": "test-state",
        "CONFIRMATION": "DEPLOY" if scenario == "startup_unowned" else "KILL",
        "ARM_CLIENT_ID": "test-client",
        "ARM_TENANT_ID": "test-tenant",
        "TF_STATE_ACCOUNT": "teststate",
        "TF_VAR_kubernetes_version": "1.36.4",
        "TF_VAR_budget_email": "owner@example.com",
        "TF_VAR_location": "test-region",
        "AZURE_ALLOWED_CIDR": "192.0.2.1/32",
        "GITHUB_REPOSITORY": owner,
        "GITHUB_STEP_SUMMARY": "",
        "GH_TOKEN": "",
        "FAKE_AZ_STATE": str(state),
        "SCENARIO": scenario,
    }
    action = (
        "expired"
        if scenario in {"expired", "not_expired", "bad_expiry", "orphaned_nodes"}
        else "kill"
    )
    if scenario == "startup_unowned":
        action = "deploy"
    command = ["bash", "scripts/azure.sh", action]
    result = subprocess.run(
        command, cwd=ROOT, env=environment, capture_output=True, text=True
    )
    record = json.loads(state.read_text())
    if scenario in {
        "unowned",
        "delete_failure",
        "budget_delete_failure",
        "list_failure",
        "bad_expiry",
        "startup_unowned",
    }:
        assert result.returncode != 0
        assert record["deleted"] == []
        if scenario == "startup_unowned":
            assert "Backend group belongs to another project" in result.stderr
    elif scenario == "not_expired":
        assert result.returncode == 0, result.stderr
        assert record["groups"] == groups
        assert record["deleted"] == []
    else:
        assert result.returncode == 0, result.stderr
        assert "KILL VERIFIED" in result.stdout
        assert record["budget"] is None
        assert record["groups"] == {}
        again = subprocess.run(
            command, cwd=ROOT, env=environment, capture_output=True, text=True
        )
        assert again.returncode == 0
        assert json.loads(state.read_text())["deleted"] == record["deleted"]


def test_kill_requires_explicit_confirmation_but_no_terraform_backend() -> None:
    """The emergency path remains usable when backend configuration is absent."""
    variables = {
        "ARM_SUBSCRIPTION_ID": "test-sub",
        "AZURE_RESOURCE_GROUP": "test-app",
        "TF_STATE_RESOURCE_GROUP": "test-state",
        "TF_STATE_ACCOUNT": "",
    }
    assert check("kill", **variables).returncode != 0
    assert check("kill", CONFIRMATION="KILL", **variables).returncode == 0


def test_dashboard_requires_configured_login_and_keeps_health_public(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Cloud operations must be authenticated while Kubernetes probes stay usable."""
    from fastapi.testclient import TestClient

    from ui.app import app

    monkeypatch.setenv("DASHBOARD_PASSWORD", "demo-test-password")
    with TestClient(app) as client:
        assert client.get("/healthz").status_code == 200
        assert client.get("/").status_code == 401
        assert client.get("/", auth=("admin", "wrong")).status_code == 401
        assert client.get("/", auth=("admin", "demo-test-password")).status_code == 200
        preflight = client.options(
            "/api/status",
            headers={
                "Origin": "https://attacker.example",
                "Access-Control-Request-Method": "GET",
            },
        )
        assert "access-control-allow-origin" not in preflight.headers


def test_dashboard_metrics_report_unavailable_prometheus_as_unknown(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import httpx
    from fastapi.testclient import TestClient

    from ui import app as dashboard

    original = httpx.AsyncClient

    def unavailable(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503)

    monkeypatch.setenv("DASHBOARD_PASSWORD", "metrics-test-password")
    monkeypatch.setattr(
        dashboard.httpx,
        "AsyncClient",
        lambda **kwargs: original(transport=httpx.MockTransport(unavailable), **kwargs),
    )
    with TestClient(dashboard.app) as client:
        response = client.get("/api/metrics", auth=("admin", "metrics-test-password"))
    assert response.status_code == 200
    metrics = response.json()
    assert metrics["prometheus_online"] is False
    assert metrics["replicas_available"] is None
    assert metrics["champion_auc"] is None
    assert metrics["feature_psi"] == {}


def test_dashboard_prediction_uses_cloud_service_endpoint(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Predictions go to the configured service rather than dashboard localhost."""
    import httpx
    from fastapi.testclient import TestClient

    from ui import app as dashboard

    original = httpx.AsyncClient
    calls = []

    def predict(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        return httpx.Response(
            200,
            json={
                "model_version": "1",
                "predictions": [{"default_probability": 0.2, "label": 0}],
            },
        )

    monkeypatch.setenv("DASHBOARD_PASSWORD", "cloud-test-password")
    monkeypatch.setattr(dashboard, "MODEL_API_URL", "http://model-api.serving.svc:8080")
    monkeypatch.setattr(
        dashboard.httpx,
        "AsyncClient",
        lambda **kwargs: original(transport=httpx.MockTransport(predict), **kwargs),
    )
    with TestClient(dashboard.app) as client:
        result = client.post(
            "/api/predict",
            json={"customer_id": "7", "env": "retrained"},
            auth=("admin", "cloud-test-password"),
        )
        assert result.status_code == 200
        assert result.json()["status"] == "success"
        assert result.json()["default_probability"] == 0.2
    assert calls == ["http://model-api.serving.svc:8080/predict"]
