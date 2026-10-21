"""FastAPI assembly for the dashboard control plane."""

from __future__ import annotations

import os
import secrets
from typing import Annotated

import httpx  # Re-exported for existing dashboard integrations and test hooks.
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBasic, HTTPBasicCredentials

from ui.routes import actions, cluster, models, overview
from ui.state import ACTION_COMMANDS, MODEL_API_URL

__all__ = ["ACTION_COMMANDS", "MODEL_API_URL", "app", "authenticate_dashboard", "httpx"]

security = HTTPBasic(auto_error=False)


async def authenticate_dashboard(
    request: Request,
    credentials: Annotated[HTTPBasicCredentials | None, Depends(security)],
) -> None:
    """Require the configured test-session credential before operations."""
    if request.url.path == "/healthz":
        return
    password = os.environ.get("DASHBOARD_PASSWORD", "")
    if not password:
        if os.environ.get("DEPLOY_TARGET") == "azure":
            raise HTTPException(status_code=503, detail="Dashboard credential missing")
        return
    valid = (
        credentials is not None
        and secrets.compare_digest(credentials.username.encode(), b"admin")
        and secrets.compare_digest(credentials.password.encode(), password.encode())
    )
    if not valid:
        raise HTTPException(
            status_code=401,
            detail="Dashboard login required",
            headers={"WWW-Authenticate": "Basic"},
        )


def _model_api_url() -> str:
    """Read the current endpoint so tests and local overrides stay effective."""
    return MODEL_API_URL


app = FastAPI(
    dependencies=[Depends(authenticate_dashboard)],
    title="MLPlatform Control Plane",
    version="1.0.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.state.model_api_url = _model_api_url
app.include_router(overview.router)
app.include_router(cluster.router)
app.include_router(models.router)
app.include_router(actions.router)


def main() -> None:
    """Run the UI server via uvicorn."""
    import uvicorn

    uvicorn.run("ui.app:app", host="0.0.0.0", port=8050, reload=True)


if __name__ == "__main__":
    main()
