# Decisions

Architecture and implementation decisions are recorded chronologically.

## 2026-10-02 — Flat, single-project repository layout

- **Decision:** Replace the nested `libs/<pkg>/src/<pkg>/` and `services/<svc>/src/<svc>/`
  layout (uv workspace with three `pyproject.toml` files and per-package test dirs) with
  a flat mono-repo: one root `pyproject.toml`, one top-level package per Python import
  root (`mlp_common/`, `ml/`, `model_api/`, `drift_monitor/`, `retrain/`, `remediator/`),
  a single `tests/` tree, and a single `docker/` directory for image definitions. Empty
  `.gitkeep`-only chart, tofu-module, and per-service test directories were removed;
  they are recreated in their owning phases.
- **Reason:** human-directed simplification ("too many repos and sub-repos for nothing").
  The nested `src` layout and multi-package workspace added depth and duplicated tooling
  without any benefit at this scale. The new layout keeps the import roots named in
  Section 5.5 stable, so no `import` statements changed, and `make` remains the command
  interface. `docs/SPEC.md` Sections 1 and 4 were updated to match.
- **Scope:** `ml/` keeps its `ml/data/` subpackage (matches Section 4 and avoids a
  gratuitous rename). The coverage gate covers `mlp_common/` and `model_api/`; the offline
  `ml/` training code is validated by its own tests rather than the coverage floor.

## 2026-10-02 — Host networking for image builds on rootless Docker (superseded)

- **Superseded** by the "Use the real Docker daemon" decision below.
- **Decision:** `make build` passes `--network=host` to `docker build` by default,
  overridable with `make build DOCKER_BUILD_NETWORK=default`.
- **Reason:** On this laptop the rootless Docker daemon's default bridge has no working
  DNS resolution — the container `/etc/resolv.conf` points at the host LAN resolver
  `172.22.47.212`, which is unreachable from the (slirp4netns) container network, and even
  explicit `--dns 10.0.2.3 / 8.8.8.8 / 1.1.1.1` fail. Host networking uses the host network
  namespace, so `pip` can reach PyPI during the build. The produced image is unaffected.
- **Evidence:** `docker run --network=host ... pip download hatchling==1.32.4` succeeded;
  default-bridge DNS lookups failed with `Temporary failure in name resolution`.

## 2026-10-02 — Use the real Docker daemon; no build-network override

- **Decision:** `make build` runs a plain `docker build` against the active Docker daemon
  (the standard rootful engine at `unix:///var/run/docker.sock`). The `--network=host`
  override was removed.
- **Reason:** human directive — use real Docker, not the rootless host-network workaround.
  A normal rootful engine has working container DNS, so no override is needed.
- **Status:** the rootful Docker Engine is not installed on this machine yet — there is no
  `/var/run/docker.sock`, no `docker.service`, no `docker` group, and `dockerd`/`docker`
  exist only under `~/.local/bin`. See BLK-003 for the human install steps. Image builds
  cannot be re-verified until the daemon is available.

## 2026-10-02 — P3 data-layer image choices

- **Decision:** Postgres uses the official `postgres:16.15-bookworm` image; MinIO uses
  `bitnamilegacy/minio` + `bitnamilegacy/minio-client` (2025.7.23 lineage); Redis stays
  on the last BSD-licensed `7.2.x` line at exactly `7.2.16-alpine3.21`.
- **Reason:** SPEC 2 requires checking MinIO availability/licensing at implementation
  time (LocalStack free tier is restricted, so it is not used). The official
  `minio/minio` pull requires authentication from this host, while the
  `bitnamilegacy` fork (community continuation after the Bitnami catalog changes)
  pulls cleanly by digest — same S3 API, so service code is unaffected. Our own Helm
  charts are used throughout, so the "avoid Bitnami charts" rule still holds.
  The `7.2-alpine3.22` redis tag does not exist upstream (alpine3.22 was never
  published for 7.2.x); `7.2.16-alpine3.21` is the latest 7.2 patch and its digest
  matches the pulled image.
- **Evidence:** `docker images --digests` confirms postgres `efedf359…`, minio
  `953d489a…`, minio-client `7a6b4b93…`, redis `29e8589c…`; `redis-server --version`
  reports `v=7.2.16`.
