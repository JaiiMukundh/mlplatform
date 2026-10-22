"""Install checksum-pinned Linux CI tools into ~/.local/bin."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

# Stable release assets and SHA256 digests from their official GitHub releases.
TOOLS = {
    "gitleaks": (
        "https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz",
        "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb",
    ),
    "actionlint": (
        "https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz",
        "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8",
    ),
    "hadolint": (
        "https://github.com/hadolint/hadolint/releases/download/v2.15.1/hadolint-linux-x86_64",
        "c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507",
    ),
    "kubeconform": (
        "https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz",
        "9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883",
    ),
    "trivy": (
        "https://github.com/aquasecurity/trivy/releases/download/v0.75.0/trivy_0.75.0_Linux-64bit.tar.gz",
        "c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f",
    ),
    "gh": (
        "https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_linux_amd64.tar.gz",
        "bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386",
    ),
    "kubectl": (
        "https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl",
        "65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8",
    ),
}


def install(name: str, destination: Path) -> None:
    """Download a pinned tool, verify its digest, and install only its binary."""
    url, expected = TOOLS[name]
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"{name}: SHA256 mismatch")
    if url.endswith(".tar.gz"):
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
            member = next(
                item
                for item in archive
                if item.isfile() and Path(item.name).name == name
            )
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError(f"{name}: binary absent from archive")
            data = stream.read()
    destination.mkdir(parents=True, exist_ok=True)
    binary = destination / name
    binary.write_bytes(data)
    binary.chmod(0o755)
    print(f"{name}: installed verified binary")


def check_manifests() -> None:
    """Validate Terraform-managed AKS manifests against pinned Kubernetes schemas."""
    import yaml

    with tempfile.TemporaryDirectory(prefix="mlp-schemas-") as directory:
        root = Path(directory)
        with tarfile.open("infra/vendor/kubernetes-schemas-1.34.12.tgz") as archive:
            for member in archive:
                if not member.isfile():
                    continue
                relative = Path(member.name)
                if len(relative.parts) == 1:
                    relative = Path("v1") / relative
                target = root / relative
                stream = archive.extractfile(member)
                if stream is None or not target.resolve().is_relative_to(root):
                    raise ValueError("invalid vendored schema member")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(stream.read())
        for source in Path("infra/vendor/schemas").rglob("*.json"):
            target = root / source.relative_to("infra/vendor/schemas")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        manifests = Path("infra/manifests")
        crds = json.loads((manifests / "crds.json").read_text())
        for crd in crds.values():
            if (
                crd["apiVersion"] != "apiextensions.k8s.io/v1"
                or crd["kind"] != "CustomResourceDefinition"
            ):
                raise ValueError("invalid custom resource definition")
            spec = crd["spec"]
            for version in spec["versions"]:
                path = (
                    root
                    / spec["group"]
                    / f"{spec['names']['kind'].lower()}_{version['name']}.json"
                )
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(version["schema"]["openAPIV3Schema"]))
        for group in ("data", "observability", "app"):
            resources = json.loads((manifests / f"{group}.json.tftpl").read_text())
            payload = "---\n".join(
                yaml.safe_dump(resource, sort_keys=False)
                for resource in resources.values()
            ).encode()
            subprocess.run(
                [
                    "kubeconform",
                    "-strict",
                    "-summary",
                    "-schema-location",
                    str(
                        root
                        / "{{ .Group }}"
                        / "{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json"
                    ),
                ],
                input=payload,
                check=True,
            )


def main() -> None:
    """Install the requested tools; failures exit nonzero."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tools", nargs="+", choices=[*TOOLS, "check-manifests"])
    args = parser.parse_args()
    for name in args.tools:
        if name == "check-manifests":
            check_manifests()
        else:
            install(name, Path.home() / ".local/bin")


if __name__ == "__main__":
    main()
