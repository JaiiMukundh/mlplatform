"""Install pinned kubectl and helm with checksum verification (P8.4).

Runs at image build time (docker/retrain.Dockerfile) as the non-root image
user into /app/bin. Versions default to docs/VERSIONS.md pins and can be
overridden with KUBECTL_VERSION / HELM_VERSION.
"""

from __future__ import annotations

import hashlib
import os
import tarfile
import urllib.request
from pathlib import Path

BIN_DIR = Path("/app/bin")
KUBECTL_VERSION = os.environ.get("KUBECTL_VERSION", "v1.37.1")
HELM_VERSION = os.environ.get("HELM_VERSION", "v3.22.0")


def _fetch(url: str) -> bytes:
    """Download one URL, failing loudly on HTTP errors."""
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def install_kubectl() -> None:
    """Install the pinned kubectl after verifying its published checksum."""
    base = f"https://dl.k8s.io/release/{KUBECTL_VERSION}/bin/linux/amd64"
    digest = _fetch(f"{base}/kubectl.sha256").decode().split()[0]
    data = _fetch(f"{base}/kubectl")
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError("kubectl checksum mismatch")
    target = BIN_DIR / "kubectl"
    target.write_bytes(data)
    target.chmod(0o755)


def install_helm(tmp: Path) -> None:
    """Install the pinned helm after verifying its published checksum."""
    archive_name = f"helm-{HELM_VERSION}-linux-amd64.tar.gz"
    digest = _fetch(f"https://get.helm.sh/{archive_name}.sha256sum").decode().split()[0]
    data = _fetch(f"https://get.helm.sh/{archive_name}")
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError("helm checksum mismatch")
    archive_path = tmp / archive_name
    archive_path.write_bytes(data)
    with tarfile.open(archive_path) as archive:
        member = archive.getmember("linux-amd64/helm")
        member.name = "helm"
        archive.extract(member, BIN_DIR)
    (BIN_DIR / "helm").chmod(0o755)


def main() -> int:
    """Install both tools into /app/bin."""
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    install_kubectl()
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        install_helm(Path(tmp))
    print("kubectl + helm installed and verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
