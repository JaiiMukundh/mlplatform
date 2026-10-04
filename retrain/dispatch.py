"""Release dispatch for retrained candidates (P8.4).

``TRIGGER_MODE=github`` POSTs a ``model-candidate-ready`` repository dispatch
(the human provisions ``GITHUB_DISPATCH_TOKEN``). ``local`` runs the exact
same release scripts the workflow would run, so the loop closes with no
GitHub connectivity. Standard library only.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import urllib.request

LOGGER = logging.getLogger(__name__)


def dispatch_candidate(
    version: str,
    *,
    trigger_mode: str | None = None,
    github_repo: str | None = None,
    github_token: str | None = None,
    release_script: str = "scripts/model_release_local.sh",
    workdir: str | None = "/app",
) -> str:
    """Announce a candidate version; return how it was released."""
    mode = trigger_mode or os.environ.get("TRIGGER_MODE", "local")
    if mode == "github":
        repo = github_repo or os.environ.get("GITHUB_REPO", "")
        token = github_token or os.environ.get("GITHUB_DISPATCH_TOKEN", "")
        if not repo or not token:
            raise ValueError(
                "TRIGGER_MODE=github needs GITHUB_REPO and GITHUB_DISPATCH_TOKEN"
            )
        payload = json.dumps(
            {
                "event_type": "model-candidate-ready",
                "client_payload": {"version": str(version)},
            }
        ).encode()
        request = urllib.request.Request(
            f"https://api.github.com/repos/{repo}/dispatches",
            data=payload,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "content-type": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            LOGGER.info(
                "github dispatch sent",
                extra={"version": str(version), "status": response.status},
            )
        return "github"
    LOGGER.info("running local release", extra={"version": str(version), "mode": mode})
    subprocess.run(["bash", release_script, str(version)], check=True, cwd=workdir)
    return "local"
