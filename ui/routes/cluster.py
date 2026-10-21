"""Routes for Kubernetes pods, logs, fault injection, and traffic bursts."""

from __future__ import annotations

import asyncio
import json
import time
from datetime import UTC, datetime
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import PlainTextResponse

from ui.state import PROMETHEUS_URL, BurstTestRequest, logger

router = APIRouter()


@router.get("/api/pods")
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
                            f"{PROMETHEUS_URL}/api/v1/query",
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


@router.get("/api/pod-logs/{namespace}/{pod_name}", response_class=PlainTextResponse)
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


@router.post("/api/kill-pod/{namespace}/{pod_name}")
async def kill_pod(namespace: str, pod_name: str) -> dict[str, Any]:
    """Delete a pod and demonstrate Kubernetes self-healing."""
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


@router.post("/api/burst-test")
async def execute_burst_test(
    request: Request,
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
                    f"{request.app.state.model_api_url()}/predict",
                    json={"customer_ids": [str(cid)]},
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
