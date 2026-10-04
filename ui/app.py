"""Central Management & Monitoring Dashboard Application.

FastAPI service providing real-time metrics, cluster workload introspection,
interactive inference testing, and streaming command execution.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import httpx
import pandas as pd
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel

logger = logging.getLogger("ui")
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)

app = FastAPI(title="MLPlatform Control Plane", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"
ACTIVE_DRIFT_QUERY = (
    "max(model_drift_detected and on(instance) up == 1) "
    "or max(model_drift_detected) or vector(0)"
)

# Track running jobs
RUNNING_JOBS: dict[str, dict[str, Any]] = {}

ACTION_COMMANDS: dict[str, str] = {
    "reset_demo": "uv run python scripts/reset_demo.py",
    "traffic_burst": (
        "uv run python scripts/traffic.py --rps 15 --duration 20 --url http://localhost:8080"
    ),
    "chaos_latency_inject": (
        "for p in $(kubectl get pods -n serving -l app.kubernetes.io/name=model-api "
        "-o jsonpath='{.items[*].metadata.name}'); do "
        "kubectl exec -n serving $p -c api -- "
        "curl -s -X POST 'http://localhost:8080/debug/latency?ms=500'; "
        'echo "Injected 500ms latency on $p"; done'
    ),
    "chaos_latency_clear": (
        "for p in $(kubectl get pods -n serving -l app.kubernetes.io/name=model-api "
        "-o jsonpath='{.items[*].metadata.name}'); do "
        "kubectl exec -n serving $p -c api -- "
        "curl -s -X POST 'http://localhost:8080/debug/latency?ms=0'; "
        'echo "Cleared latency on $p"; done'
    ),
    "chaos_pod_kill": "bash scripts/chaos_pod.sh",
    "demo_infra": "bash scripts/chaos_alert.sh",
    "simulate_drift": (
        "uv run python scripts/simulate_drift.py --scenario both && "
        "uv run python scripts/traffic.py --rps 30 --duration 25 --url http://localhost:8080"
    ),
    "demo_model": "bash scripts/demo_model.sh",
    "run_gate": "bash scripts/run_gate.sh",
    "feast_rematerialize": "make feast-rematerialize",
    "e2e_tests": "make e2e",
}


class PredictRequest(BaseModel):
    customer_id: str | int = "1"


class ActionRequest(BaseModel):
    action: str


@app.get("/", response_class=HTMLResponse)
async def serve_index() -> HTMLResponse:
    """Serve the single-page application dashboard."""
    index_file = TEMPLATES_DIR / "index.html"
    if not index_file.exists():
        raise HTTPException(status_code=404, detail="Dashboard template not found.")
    return HTMLResponse(content=index_file.read_text(encoding="utf-8"))


@app.get("/api/status")
async def get_system_status() -> dict[str, Any]:
    """Retrieve system status across K8s, serving, data, and observability."""
    status: dict[str, Any] = {
        "timestamp": datetime.now(UTC).isoformat(),
        "cluster": "unknown",
        "nodes_ready": 0,
        "nodes_total": 0,
        "serving_model": None,
        "prometheus_online": False,
        "mlflow_online": False,
        "minio_online": False,
        "drift_detected": False,
    }

    # 1. K8s Nodes
    try:
        proc = await asyncio.create_subprocess_exec(
            "kubectl",
            "get",
            "nodes",
            "-o",
            "json",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        if proc.returncode == 0:
            nodes_data = json.loads(stdout.decode())
            items = nodes_data.get("items", [])
            status["nodes_total"] = len(items)
            ready_count = 0
            for node in items:
                conds = node.get("status", {}).get("conditions", [])
                for c in conds:
                    if c.get("type") == "Ready" and c.get("status") == "True":
                        ready_count += 1
                        break
            status["nodes_ready"] = ready_count
            status["cluster"] = "Kind (mlp)" if ready_count > 0 else "degraded"
    except Exception as exc:
        logger.debug("Failed querying nodes: %s", exc)

    # 2. Model API
    async with httpx.AsyncClient(timeout=1.5) as client:
        try:
            resp = await client.get("http://localhost:8080/model-info")
            if resp.status_code == 200:
                status["serving_model"] = resp.json()
        except Exception:
            status["serving_model"] = None

        # 3. Prometheus
        try:
            resp = await client.get("http://localhost:9090/-/healthy")
            status["prometheus_online"] = resp.status_code == 200
        except Exception:
            status["prometheus_online"] = False

        # 4. MLflow
        try:
            resp = await client.get("http://localhost:5000/health")
            status["mlflow_online"] = resp.status_code == 200
        except Exception:
            status["mlflow_online"] = False

        # 5. MinIO
        try:
            resp = await client.get("http://localhost:9000/minio/health/live")
            status["minio_online"] = resp.status_code == 200
        except Exception:
            status["minio_online"] = False

        # 6. Drift Flag from Prometheus
        try:
            resp = await client.get(
                "http://localhost:9090/api/v1/query",
                params={"query": ACTIVE_DRIFT_QUERY},
            )
            if resp.status_code == 200:
                data = resp.json().get("data", {}).get("result", [])
                if data:
                    val = float(data[0].get("value", [0, 0])[1])
                    status["drift_detected"] = val >= 1.0
        except Exception:
            status["drift_detected"] = False

    return status


@app.get("/api/metrics")
async def get_metrics() -> dict[str, Any]:
    """Query Prometheus for live golden signals and drift measurements."""
    metrics: dict[str, Any] = {
        "rps": 0.0,
        "p50_latency_ms": 0.0,
        "p95_latency_ms": 0.0,
        "error_rate_pct": 0.0,
        "replicas_available": 2,
        "replicas_desired": 2,
        "model_drift_detected": 0,
        "champion_auc": 0.835,
        "candidate_auc": 0.0,
        "feature_psi": {
            "pay_0": 0.005,
            "limit_bal": 0.008,
            "bill_amt1": 0.003,
            "pay_amt1": 0.004,
            "age": 0.002,
            "education": 0.001,
        },
    }

    async with httpx.AsyncClient(timeout=2.0) as client:
        # Helper to query Prometheus scalar
        async def prom_scalar(query: str, default: float = 0.0) -> float:
            try:
                r = await client.get(
                    "http://localhost:9090/api/v1/query", params={"query": query}
                )
                if r.status_code == 200:
                    res = r.json().get("data", {}).get("result", [])
                    if res:
                        return float(res[0].get("value", [0, 0])[1])
            except Exception:
                pass
            return default

        # Query metrics concurrently
        p50_q = (
            "histogram_quantile(0.50, sum(rate("
            "http_request_duration_seconds_bucket{namespace='serving',path='/predict'}[5m]"
            ")) by (le)) * 1000"
        )
        p95_q = (
            "histogram_quantile(0.95, sum(rate("
            "http_request_duration_seconds_bucket{namespace='serving',path='/predict'}[5m]"
            ")) by (le)) * 1000"
        )
        err_q = (
            "(sum(rate(http_requests_total{namespace='serving',status=~'5..'}[2m])) "
            "or vector(0)) / (sum(rate(http_requests_total{namespace='serving'}[2m])) "
            "or vector(1)) * 100"
        )
        rep_avail_q = (
            "kube_deployment_status_replicas_available{"
            "deployment='model-api', namespace='serving'}"
        )
        rep_des_q = (
            "kube_deployment_spec_replicas{deployment='model-api', namespace='serving'}"
        )

        tasks = [
            prom_scalar(
                "sum(rate(http_requests_total{namespace='serving',path='/predict'}[1m]))",
                0.0,
            ),
            prom_scalar(p50_q, 8.5),
            prom_scalar(p95_q, 16.0),
            prom_scalar(err_q, 0.0),
            prom_scalar(rep_avail_q, 2.0),
            prom_scalar(rep_des_q, 2.0),
            prom_scalar(ACTIVE_DRIFT_QUERY, 0.0),
            prom_scalar("model_champion_auc", 0.835),
            prom_scalar("model_candidate_auc", 0.0),
        ]

        results = await asyncio.gather(*tasks)

        metrics["rps"] = round(results[0], 2)
        metrics["p50_latency_ms"] = round(max(results[1], 0.0), 1)
        metrics["p95_latency_ms"] = round(max(results[2], 0.0), 1)
        metrics["error_rate_pct"] = round(max(results[3], 0.0), 2)
        metrics["replicas_available"] = int(results[4])
        metrics["replicas_desired"] = int(results[5])
        metrics["model_drift_detected"] = int(results[6])
        metrics["champion_auc"] = round(results[7], 4)
        metrics["candidate_auc"] = round(results[8], 4)

        # Query PSI per feature if available
        try:
            r = await client.get(
                "http://localhost:9090/api/v1/query",
                params={"query": "model_feature_psi"},
            )
            if r.status_code == 200:
                res = r.json().get("data", {}).get("result", [])
                for item in res:
                    feat = item.get("metric", {}).get("feature")
                    if feat:
                        metrics["feature_psi"][feat] = round(
                            float(item.get("value", [0, 0])[1]), 4
                        )
        except Exception:
            pass

    return metrics


@app.get("/api/pods")
async def get_pods() -> list[dict[str, Any]]:
    """Retrieve pod status across serving, data, and observability namespaces."""
    pods: list[dict[str, Any]] = []
    try:
        proc = await asyncio.create_subprocess_exec(
            "kubectl",
            "get",
            "pods",
            "-A",
            "-o",
            "json",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        stdout, _ = await proc.communicate()
        if proc.returncode == 0:
            data = json.loads(stdout.decode())
            now = datetime.now(UTC)
            for item in data.get("items", []):
                ns = item.get("metadata", {}).get("namespace", "")
                if ns not in {"serving", "staging", "data", "observability"}:
                    continue
                name = item.get("metadata", {}).get("name", "")
                created_str = item.get("metadata", {}).get("creationTimestamp", "")
                age_str = "?"
                if created_str:
                    try:
                        created = datetime.fromisoformat(
                            created_str.replace("Z", "+00:00")
                        )
                        seconds = int((now - created).total_seconds())
                        if seconds < 60:
                            age_str = f"{seconds}s"
                        elif seconds < 3600:
                            age_str = f"{seconds // 60}m"
                        else:
                            age_str = f"{seconds // 3600}h"
                    except Exception:
                        pass

                statuses = item.get("status", {}).get("containerStatuses", [])
                ready_count = sum(1 for c in statuses if c.get("ready"))
                total_containers = len(statuses) or 1
                ready_str = f"{ready_count}/{total_containers}"
                restarts = sum(c.get("restartCount", 0) for c in statuses)
                phase = item.get("status", {}).get("phase", "Unknown")

                pods.append(
                    {
                        "name": name,
                        "namespace": ns,
                        "status": phase,
                        "ready": ready_str,
                        "restarts": restarts,
                        "age": age_str,
                    }
                )

            # Enrich serving pods with real-time Prometheus RPS and traffic share %
            serving_pods = [p for p in pods if p["namespace"] == "serving"]
            if serving_pods:
                pod_rps_map: dict[str, float] = {}
                try:
                    pod_query = (
                        "sum(rate(http_requests_total"
                        "{namespace='serving'}[1m])) by (pod)"
                    )
                    async with httpx.AsyncClient(timeout=1.0) as client:
                        r = await client.get(
                            "http://localhost:9090/api/v1/query",
                            params={"query": pod_query},
                        )
                        if r.status_code == 200:
                            for item in r.json().get("data", {}).get("result", []):
                                pname = item.get("metric", {}).get("pod")
                                val = float(item.get("value", [0, 0])[1])
                                if pname:
                                    pod_rps_map[pname] = round(val, 2)
                except Exception:
                    pass

                healthy_serving = [
                    p
                    for p in serving_pods
                    if p["status"] == "Running" and p["ready"] == "1/1"
                ]
                total_active_rps = sum(
                    pod_rps_map.get(p["name"], 0.0) for p in healthy_serving
                )

                for p in serving_pods:
                    is_healthy = p["status"] == "Running" and p["ready"] == "1/1"
                    if not is_healthy:
                        p["traffic_share_pct"] = 0.0
                        p["traffic_rps"] = 0.0
                    elif len(healthy_serving) == 1:
                        p["traffic_share_pct"] = 100.0
                        p["traffic_rps"] = max(
                            pod_rps_map.get(p["name"], 0.0), total_active_rps
                        )
                    else:
                        if total_active_rps > 0.05:
                            p["traffic_rps"] = pod_rps_map.get(p["name"], 0.0)
                            p["traffic_share_pct"] = round(
                                (p["traffic_rps"] / total_active_rps) * 100, 1
                            )
                        else:
                            p["traffic_rps"] = round(pod_rps_map.get(p["name"], 0.0), 2)
                            p["traffic_share_pct"] = round(
                                100.0 / len(healthy_serving), 1
                            )

    except Exception as exc:
        logger.error("Failed to query pods: %s", exc)

    return sorted(pods, key=lambda x: (x["namespace"], x["name"]))


@app.get("/api/pod-logs/{namespace}/{pod_name}", response_class=PlainTextResponse)
async def get_pod_logs(namespace: str, pod_name: str) -> PlainTextResponse:
    """Fetch container logs for a specific pod."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "kubectl",
            "logs",
            "-n",
            namespace,
            pod_name,
            "--all-containers=true",
            "--tail=150",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        stdout, _ = await proc.communicate()
        return PlainTextResponse(content=stdout.decode("utf-8", errors="replace"))
    except Exception as exc:
        return PlainTextResponse(
            content=f"Error retrieving logs: {exc}", status_code=500
        )


@app.post("/api/kill-pod/{namespace}/{pod_name}")
async def kill_pod(namespace: str, pod_name: str) -> dict[str, Any]:
    """Delete a pod asynchronously to demonstrate real-time Kubernetes self-healing."""
    if namespace not in ("serving", "staging", "data", "observability"):
        raise HTTPException(status_code=400, detail="Invalid namespace")
    try:
        proc = await asyncio.create_subprocess_exec(
            "kubectl",
            "delete",
            "pod",
            pod_name,
            "-n",
            namespace,
            "--now",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        stdout, _ = await proc.communicate()
        out = stdout.decode("utf-8", errors="replace").strip()
        return {
            "status": "success" if proc.returncode == 0 else "error",
            "pod": pod_name,
            "namespace": namespace,
            "output": out,
        }
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


class BurstTestRequest(BaseModel):
    count: int = 10


@app.post("/api/burst-test")
async def execute_burst_test(
    req: BurstTestRequest | None = None,
) -> dict[str, Any]:
    """Execute rapid concurrent prediction requests to verify zero dropped calls."""
    actual_req = req or BurstTestRequest()
    count = max(1, min(actual_req.count, 50))
    t0 = time.perf_counter()
    async with httpx.AsyncClient(timeout=4.0) as client:

        async def single_call(cid: int):
            try:
                r = await client.post(
                    "http://localhost:8080/predict", json={"customer_ids": [str(cid)]}
                )
                return r.status_code == 200
            except Exception:
                return False

        tasks = [single_call((i % 30000) + 1) for i in range(count)]
        results = await asyncio.gather(*tasks)

    elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
    success = sum(1 for ok in results if ok)
    failed = count - success
    return {
        "status": "success",
        "total": count,
        "successful": success,
        "failed": failed,
        "success_rate_pct": round((success / count) * 100, 1),
        "total_elapsed_ms": elapsed_ms,
        "avg_latency_ms": round(elapsed_ms / count, 1) if count > 0 else 0,
        "zero_downtime": failed == 0,
    }


@app.post("/api/predict")
async def execute_predict(req: PredictRequest) -> dict[str, Any]:
    """Execute live prediction via model-api for a customer ID."""
    t0 = time.perf_counter()
    async with httpx.AsyncClient(timeout=5.0) as client:
        try:
            resp = await client.post(
                "http://localhost:8080/predict",
                json={"customer_ids": [str(req.customer_id)]},
            )
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 2)
            if resp.status_code == 200:
                data = resp.json()
                preds = data.get("predictions", [])
                if preds:
                    pred_item = preds[0]
                    prob = float(pred_item.get("default_probability", 0.0))
                    fallback_label = int(prob >= 0.5)
                    label = int(
                        pred_item.get(
                            "label", pred_item.get("prediction", fallback_label)
                        )
                    )
                    risk = (
                        "HIGH RISK (DEFAULT)" if label == 1 else "LOW RISK (APPROVED)"
                    )
                    return {
                        "status": "success",
                        "customer_id": str(req.customer_id),
                        "model_version": data.get("model_version", "unknown"),
                        "default_probability": round(prob, 4),
                        "prediction": label,
                        "risk_level": risk,
                        "latency_ms": elapsed_ms,
                    }
            return {
                "status": "error",
                "message": (
                    f"Inference failed with status {resp.status_code}: {resp.text}"
                ),
                "latency_ms": elapsed_ms,
            }
        except Exception as exc:
            return {
                "status": "error",
                "message": f"Connection error: {exc}",
                "latency_ms": round((time.perf_counter() - t0) * 1000, 2),
            }


@app.get("/api/customer-profile/{customer_id}")
async def get_customer_profile(customer_id: int) -> dict[str, Any]:
    """Retrieve raw borrower profile from latest features."""
    try:
        parquet_path = Path("data/features_latest.parquet")
        if not parquet_path.exists():
            return {"status": "not_found", "message": "Dataset not found"}
        df = pd.read_parquet(parquet_path, filters=[("customer_id", "==", customer_id)])
        if df.empty:
            return {
                "status": "not_found",
                "message": f"Customer {customer_id} not found",
            }
        row = df.iloc[0].to_dict()
        education_map = {
            1: "Graduate School",
            2: "University",
            3: "High School",
            4: "Others",
        }
        marriage_map = {1: "Married", 2: "Single", 3: "Others"}
        sex_map = {1: "Male", 2: "Female"}
        return {
            "status": "success",
            "customer_id": customer_id,
            "limit_bal": float(row.get("limit_bal", 0)),
            "age": int(row.get("age", 0)),
            "sex": sex_map.get(int(row.get("sex", 1)), "Other"),
            "education": education_map.get(int(row.get("education", 2)), "University"),
            "marriage": marriage_map.get(int(row.get("marriage", 2)), "Single"),
            "pay_0": int(row.get("pay_0", 0)),
            "bill_amt1": float(row.get("bill_amt1", 0)),
            "pay_amt1": float(row.get("pay_amt1", 0)),
            "features": {
                k: float(v)
                for k, v in row.items()
                if k not in ("customer_id", "event_timestamp")
            },
        }
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


@app.post("/api/action")
async def trigger_action(req: ActionRequest) -> dict[str, Any]:
    """Trigger an action by name and return a streaming execution ID."""
    if req.action not in ACTION_COMMANDS:
        avail = list(ACTION_COMMANDS.keys())
        raise HTTPException(
            status_code=400,
            detail=f"Unknown action: '{req.action}'. Available: {avail}",
        )

    execution_id = str(uuid.uuid4())
    cmd = ACTION_COMMANDS[req.action]
    RUNNING_JOBS[execution_id] = {
        "action": req.action,
        "command": cmd,
        "created_at": datetime.now(UTC).isoformat(),
        "status": "pending",
    }
    return {
        "execution_id": execution_id,
        "action": req.action,
        "command": cmd,
    }


@app.get("/api/stream/{execution_id}")
async def stream_action_output(execution_id: str):
    """Server-Sent Events endpoint streaming real-time subprocess stdout/stderr."""
    if execution_id not in RUNNING_JOBS:
        raise HTTPException(status_code=404, detail="Execution ID not found.")

    job = RUNNING_JOBS[execution_id]
    cmd = job["command"]

    async def event_generator():
        start_payload = {
            "type": "start",
            "command": cmd,
            "timestamp": datetime.now(UTC).isoformat(),
        }
        yield f"data: {json.dumps(start_payload)}\n\n"
        job["status"] = "running"

        try:
            process = await asyncio.create_subprocess_shell(
                cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
                cwd=str(BASE_DIR),
            )

            assert process.stdout is not None
            while True:
                line = await process.stdout.readline()
                if not line:
                    break
                line_text = line.decode("utf-8", errors="replace")
                yield f"data: {json.dumps({'type': 'stdout', 'line': line_text})}\n\n"

            exit_code = await process.wait()
            job["status"] = "completed" if exit_code == 0 else "failed"
            job["exit_code"] = exit_code
            yield f"data: {json.dumps({'type': 'end', 'exit_code': exit_code})}\n\n"
        except Exception as exc:
            job["status"] = "error"
            yield f"data: {json.dumps({'type': 'error', 'message': str(exc)})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


def main():
    """Run the UI server via uvicorn."""
    import uvicorn

    uvicorn.run("ui.app:app", host="0.0.0.0", port=8050, reload=False)


if __name__ == "__main__":
    main()
