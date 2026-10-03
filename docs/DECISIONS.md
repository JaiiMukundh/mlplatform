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

## 2026-10-02 — Drive kind via CLI from OpenTofu, not the kind provider

- **Decision:** `infra/modules/cluster_kind` renders `kind-config.yaml` from its
  variables and manages the cluster with `terraform_data` + `local-exec` running
  `kind create/delete cluster` (same imperative pattern as the registry module),
  instead of the `tehcyx/kind` provider's `kind_cluster` resource.
- **Reason:** provider v0.11.0 (latest) bundles kind 0.31.0, whose kubeadm cannot
  init the pinned Kubernetes v1.37.0 nodes (`kubeadm init exit status 1`,
  reproduced twice on a clean slate), while the kind v0.33.0 CLI creates the
  identical config cleanly (proven with a probe cluster). Downgrading K8s to suit
  the provider would diverge CLI and IaC; driving the verified CLI keeps one
  Kubernetes version everywhere. Module inputs/outputs are unchanged, so
  `infra/envs/local` is unaffected.
- **Consequence:** `make up` applies in two phases (cluster targets first, then
  everything): the kubernetes/helm providers stat the kubeconfig file at
  configuration time, so they can only be configured after the cluster has
  written it. Both phases are no-ops when converged.

## 2026-10-02 — Harden data-layer init jobs for cold starts

- **Decision:** the postgres init job waits for `pg_isready` and the minio buckets
  job waits for `mc alias set` to succeed (10-minute budget) before doing work;
  the buckets job runs under `/bin/bash` with a writable `$HOME` emptyDir.
- **Reason:** on a fresh cluster the nodes pull ~800MB of images while the helm
  hooks already run; without waits the jobs burn their backoff budget. Separately,
  the buckets job died instantly twice: `/bin/sh` in the minio-client image is
  dash (no `pipefail`), and `mc` needs a writable `$HOME` under the read-only
  root filesystem. Diagnosed by replicating the container with debug pods.

## 2026-10-02 — AWS parity module choices (plan-only)

- **Decision:** VPC and EKS use the community modules (`terraform-aws-modules/vpc`
  6.7.3, `.../eks` 21.26.0) as SPEC P3.6 names; S3/RDS/ECR/IAM/budget are raw
  `aws_*` resources. AZ names derive from the region string (`<region>a/b`) and
  the RDS engine pins major `"16"` only.
- **Reason:** wiring the two big modules blind is already risky; raw resources keep
  the rest exactly reviewable. `data.aws_availability_zones` and exact RDS minors
  need live AWS APIs, which `plan` with dummy credentials cannot reach — derived
  AZs and a major-version pin keep `validate`/`plan` offline-capable; the exact
  minor is pinned at the P9.6 human apply. IRSA roles mirror the local static
  creds (model-api read-only; retrain/mlflow read-write).

## 2026-10-02 — Upstream charts vendored (P5)

- **Decision:** `infra/charts/` commits the pinned `.tgz` files
  (`kube-prometheus-stack-91.8.2`, `loki-7.3.0`, `alloy-1.13.0`,
  `metrics-server-3.14.0`) and tofu installs from those local files instead
  of the helm repositories.
- **Reason:** the upstream asset host (`release-assets.githubusercontent.com`)
  consistently times out for helm/tofu chart downloads on this laptop, while a
  direct `curl` of the same pinned URLs succeeds and the files are byte-identical
  valid gzip. Vendoring keeps every apply reproducible and offline-capable.

## 2026-10-02 — Remediator scales the HPA floor, not Deployment replicas (P5.6)

- **Decision:** on `HighP95Latency` the remediator patches the `model-api`
  HPA `minReplicas` +2 (capped at HPA max) instead of scaling the Deployment.
- **Reason:** the HPA controller owns Deployment replicas; a manual
  `scale` would be reverted within seconds (controller fight). Raising the HPA
  floor is the conflict-free equivalent and self-documents in the HPA spec.
  Verified by the P5.7 drill (floor 2→4, Grafana annotation, then restore).

## 2026-10-03 — Persist the inotify limits and enforce them with a preflight (P6)

- **Decision:** ship `infra/sysctl/99-kind-inotify.conf` (the drop-in the human
  installs once as root) and `scripts/check_host.sh`, which fails loudly when
  `fs.inotify.max_user_instances < 512` or `fs.inotify.max_user_watches < 524288`.
  The check runs as `make preflight` and as the first step of `make up`.
- **Reason:** BLK-002 was fixed with a runtime-only `sysctl -w`, so the host
  reboot on 2026-10-03 silently reverted the limits to the default 128, which
  killed kube-proxy and CoreDNS and took down all in-cluster DNS (BLK-004). A
  persisted drop-in makes the fix durable, and a preflight turns a confusing
  cluster-wide outage into an immediate, actionable error before `make up`
  builds anything. This follows the operating contract: fail loudly, and keep
  `make` a reliable interface.
- **Scope:** values are read from `/proc/sys` so the check needs no extra tools
  and no privileges; `make bootstrap` is deliberately left untouched because it
  regenerates `docs/VERSIONS.md` from scratch and would drop the phase-specific
  pins appended in later phases.

## 2026-10-03 — Feast config rendering and offline filename (P6.2)

- **Decision:** `feature_repo/feature_store.yaml` is not committed. The versioned
  artifact is `feature_repo/feature_store.yaml.tmpl` plus `feature_repo/render_config.py`,
  which substitutes `${POSTGRES_*}`, `FEAST_POSTGRES_DB`, and `${REDIS_*}`
  placeholders from the environment and fails loudly when any value is missing.
- **Reason:** SPEC P6.2 requires a SQL registry whose path embeds the Postgres
  password and explicitly says to render the file from a template with env vars
  rather than commit creds. Keeping the rendered file out of git and out of the
  image (`.gitignore` + `.dockerignore`) satisfies the "no secrets in git" rule;
  in-cluster the values arrive from the `postgres-auth` Secret.
- **Offline filename:** the generator writes `data/features.parquet`, while SPEC
  P6.2 names the FileSource `s3://feast-offline/customer_features.parquet`. The
  setup Job publishes `features.parquet` to MinIO under the spec's name, so
  `definitions.py` can use the exact path P6.2 states without changing the data
  tooling. `labels.parquet` is uploaded unchanged for the P6.4 entity frame.

- 2026-10-03: Training uses s3fs 2026.9.0 and boto3 1.43.106. PyPI aiobotocore 3.9.2 requires botocore <1.43.107; newer boto3 cannot resolve. Preserve the newest compatible exact pin for Feast S3 retrieval.
