"""Routes for starting dashboard actions and streaming their output."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from ui.state import ACTION_COMMANDS, BASE_DIR, RUNNING_JOBS, ActionRequest

router = APIRouter()


@router.post("/api/action")
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


@router.get("/api/stream/{target}")
async def stream_action_output(target: str):
    """Server-Sent Events endpoint streaming real-time subprocess stdout/stderr."""
    cmd = ACTION_COMMANDS.get(target)
    job = None
    if cmd is None and target in RUNNING_JOBS:
        job = RUNNING_JOBS[target]
        cmd = job.get("command")

    if not cmd:
        avail = list(ACTION_COMMANDS.keys())
        raise HTTPException(
            status_code=404,
            detail=(f"Action or job '{target}' not found. Available actions: {avail}"),
        )

    async def event_generator():
        yield f"data: $ {cmd}\n\n"
        if job:
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
                line_text = line.decode("utf-8", errors="replace").rstrip("\r\n")
                if line_text:
                    for subline in line_text.replace("\r", "\n").splitlines():
                        subline_clean = subline.strip("\r")
                        if subline_clean:
                            yield f"data: {subline_clean}\n\n"

            exit_code = await process.wait()
            if job:
                job["status"] = "completed" if exit_code == 0 else "failed"
                job["exit_code"] = exit_code

            if exit_code == 0:
                yield "data: [PROCESS COMPLETED SUCCESSFULLY (EXIT 0)]\n\n"
            else:
                yield f"data: [PROCESS FAILED (EXIT {exit_code})]\n\n"
            yield "data: [DONE]\n\n"
        except Exception as exc:
            if job:
                job["status"] = "error"
            yield f"data: [ERROR: {exc!s}]\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )
