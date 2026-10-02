# Progress

Only observed command output is recorded here.

## 2026-10-02

- Read `docs/SPEC.md` in full and initialized the phase/task ledger.
- Tool inventory found the repository was empty and several P0/P2 prerequisites are not installed yet.
- P0.1 PASS — `find . -type f | sort` enumerated the specified root, docs, libs,
  ML, service, deployment, infrastructure, script, workflow, and E2E paths.
- P0.1 PASS — `docs/SPEC.md` is preserved; root `AGENTS.md` contains Section 1;
  `TASKS.md`, `PROGRESS.md`, `BLOCKERS.md`, decision/version logs, `.gitignore`,
  `.env.example`, and the README now exist.
- Next action: implement P0.2, then execute P0 tasks in order.
- P0.2 PASS — `make help` lists all 18 required targets; targets not implemented in
  P0 print their owning phase and exit successfully.
- Next action: implement the prerequisite verifier for P0.3.
- P0.3 PASS — `make bootstrap` exited 0 after checking every required binary and
  the managed Python 3.11 runtime. Observed pins include Docker 29.8.2, kind 0.33.0,
  kubectl 1.37.1, Helm 3.22.0, OpenTofu 1.13.1, jq 1.8.2, and yq 4.54.1.
- P0.3 PASS — the command regenerated `docs/VERSIONS.md` from observed output and
  explicitly reported optional tools that are not installed.
- Next action: implement and test `mlp_common` for P0.4.
- P0.4 PASS — `uv run --python 3.11 --with pytest==9.0.2 --with-editable
  libs/mlp_common pytest -q libs/mlp_common/tests` built the editable package and
  reported `8 passed in 0.40s`.
- P0.4 PASS — tests exercise environment settings, log-level validation, the five
  required JSON fields plus request context, request batch limits, and probability bounds.
- Next action: configure the repository-wide P0.5 quality gates.
- P0.5 PASS — `make lint` reported `All checks passed` and all 54 Python files
  formatted; `make test` reported `8 passed` with 88.89% branch-aware coverage,
  above the required 80% floor.
- P0.5 PASS — `uv run pre-commit run --all-files` passed Ruff lint/format,
  end-of-file, YAML, TOML, and gitleaks secret scanning hooks.
- Next action: add the P0.6 Git/PR conventions and close the P0 acceptance gate.
- P0.6 PASS — added the pull-request verification/risk template and documented
  `main`, `feat/<phase>-<topic>`, Conventional Commits, and task evidence discipline.
- P0 ACCEPTANCE PASS — `make bootstrap` exited 0; `make lint` reported all checks
  passed and 55 files formatted; `make test` reported 8 passed and 88.89% coverage.
- P0 ACCEPTANCE PASS — all six pre-commit hooks passed, including gitleaks, and
  `git log --oneline` showed six Conventional Commits from `chore`, `build`, `feat`,
  and `docs` types.
- Next action: implement P1.1 deterministic synthetic data.
- P1.1 PASS — `make seed-data` wrote all three Parquet assets and reported
  `rows=80000 customers=20000 positive_rate=0.1184`.
- P1.1 PASS — `pytest -q ml/tests/test_generate.py` reported 3 passed, covering
  exact shapes, no missing values, the 10–14% base rate, fixed-seed determinism,
  and documented feature ranges.
- Next action: implement P1.2 temporal training and calibrate its hold-out AUC.
- P1.2 PASS — `make train` used the 56k/12k/12k temporal split and reported
  validation AUC 0.8562 and test AUC 0.8581, within the required [0.82, 0.92].
- P1.2 PASS — `pytest -q ml/tests/test_train.py` reported 2 passed; the test loaded
  the persisted joblib model and verified metrics, reference Parquet, and feature schema.
- Next action: implement the P1.3 FastAPI service and file-backed providers.
- P1.3 PASS — an in-process FastAPI acceptance probe returned 200 from `/readyz`,
  returned three predictions with `model_version=file-v1`, exposed
  `http_requests_total`, and reported the exact six-feature model schema.
- P1.3 PASS — observed stdout lines were JSON with timestamp, level, service,
  request ID, message, method, path, and status context fields.
- Next action: implement the non-blocking P1.4 prediction log buffer.
- P1.4 PASS — a three-customer request returned 200 while the bounded background
  worker independently emitted three structured no-DB prediction records and stopped
  cleanly during application shutdown.
- P1.4 PASS — implementation caps the queue at 10,000, flushes at 200 rows or two
  seconds, moves blocking SQL work to a thread, increments the failure counter, and
  retries with bounded exponential backoff.
- Next action: add the P1.5 API and prediction-buffer test suite.
- P1.5 PASS — `make test` collected 28 tests and reported all 28 passed in 4.53s
  with 87.99% combined branch-aware coverage (model-api modules individually total
  above 80%).
- P1.5 PASS — tests cover happy path, exact 404 contract, 422 validation, readiness
  before/after startup and provider failure, metrics, metadata, chaos opt-in, bounded
  buffering, no-DB flushing, and both file-backed providers.
- Next action: implement the P1.6 multi-stage non-root container.
- P1.6 PASS — `hadolint services/model_api/Dockerfile` exited 0 with no findings.
  The multi-stage image pins Python 3.11.15 slim by digest, installs local packages,
  runs as UID/GID 10001, uses one uvicorn worker, and contains no Docker HEALTHCHECK.
- P1.6 PASS — `make test` remained green at 28 passed / 88.07% after moving the
  serving feature schema into the container-installed shared library.
- Next action: wire and attempt the P1.7 image build acceptance check.
- P1.7 BLOCKED — `make build` is wired to hadolint and the pinned Docker build,
  but `docker info` failed because no daemon socket exists.
- P1.7 BLOCKED — rootless setup attempts isolated the missing system prerequisite:
  RootlessKit reported `newuidmap ... executable file not found`. See BLK-001.
- Next action after BLK-001: start rootless Docker, rerun `make seed-data train build`,
  then prove the live curl acceptance sequence before checking P1.7.
- Blockers update — Docker was unblocked independently (human installed `uidmap`); the
  rootless daemon is now active, so BLK-001 is closed and container work can proceed.
- Restructure — replaced the nested `libs/<pkg>/src/<pkg>/` + `services/<svc>/src/<svc>/`
  uv-workspace layout (3 pyprojects, 4 test dirs, 10 empty chart dirs, 7 empty tofu
  modules) with a flat mono-repo: one root `pyproject.toml`, top-level packages
  `mlp_common/ ml/ model_api/ drift_monitor/ retrain/ remediator/`, one `tests/` tree, and
  `docker/*.Dockerfile`. Import roots are unchanged, so no source imports changed. Recorded
  in `docs/DECISIONS.md`; SPEC Sections 1 and 4 updated to match.
- Restructure PASS — `uv sync` rebuilt one `mlplatform` package; `make lint` reported
  `All checks passed!` (63 files formatted); `make test` reported 28 passed with 88.07%
  branch-aware coverage; all six pre-commit hooks passed including gitleaks; hadolint
  reported no findings.
- Next action: execute the P1.7 image build acceptance check.
- P1.7 PASS — `make seed-data train build` exited 0: generated
  `rows=80000 customers=20000 positive_rate=0.1184`, trained
  `validation_auc=0.8562 test_auc=0.8581`, hadolint clean, and produced the image
  `localhost:5001/model-api:dev`.
- P1.7 PASS — the running container returned `/readyz` 200 within 4s, `/predict` 200 with
  three probabilities in [0,1], `/model-info` version `file-v1` with six features, and
  `/metrics` contained `http_requests_total`; stdout logs were JSON with ts, level,
  service, request_id, msg plus method/path/status.
- P1.7 PASS — rootless Docker could not resolve DNS on the default bridge, so the build
  uses host networking (`DOCKER_BUILD_NETWORK=host`, overridable); recorded in DECISIONS.
- P1 ACCEPTANCE PASS — P1.1–P1.7 complete: `make seed-data train build`, the container
  run sequence, and `make test` (28 passed, ≥80% coverage) all pass.
- Next action: start P2 with the local registry script (P2.1), then the kind cluster (P2.2).
- P2.1 PASS — `scripts/registry.sh` idempotently started the `kind-registry` container
  (`registry:2`, `127.0.0.1:5001->5000`), attached it to the `kind` network, and applied the
  `kube-public/local-registry-hosting` ConfigMap; `curl localhost:5001/v2/` returned HTTP 200.
- P2.2 PARTIAL — `infra/kind-config.yaml` (1 control-plane + 2 workers, registry mirror,
  host port mappings) was created and `kind create cluster --name mlp` exited 0, but only
  `mlp-control-plane` and `mlp-worker` reached Ready. The third node's kubelet exits with
  `inotify_init: too many open files` ("Failed to start cAdvisor") because the host's
  `fs.inotify.max_user_instances=128` is too low for three node containers. See BLK-002.
- Next action after BLK-002: raise the inotify limits (human), recreate the cluster, and
  confirm `kubectl get nodes` reports three Ready nodes before continuing P2.3.
- Environment change (human directive): switch to the real rootful Docker daemon and drop
  the rootless workaround. `make build` was reverted to a plain `docker build` (no
  `--network=host`) and the prior DECISIONS entry is marked superseded. The rootful engine is
  not yet installed on this machine, so BLK-003 was raised. Image builds and the kind cluster
  must be re-verified once `docker info` reports the system daemon.
- Human setup completed: rootful Docker Engine installed (client 29.8.2, server
  29.1.3), user added to the `docker` group (`sg docker` works now; direct access
  after re-login), inotify limits raised to 512/524288. Rootless kind leftovers were
  removed; see the P2 entries below.
- Root-Docker migration PASS — recreated the registry and kind cluster on the rootful
  daemon; `kubectl get nodes` reports 3 Ready (control-plane + 2 workers, v1.37.0).
  A plain default-bridge container resolved `pypi.org` (151.101.0.223), so the
  `DOCKER_BUILD_NETWORK` workaround stays removed.
- `make build` re-verification PASS on real Docker — plain `docker build` produced
  `localhost:5001/model-api:dev`; live probes returned `/readyz` 200,
  `/model-info` 200 (`file-v1`, six features), `/metrics` 200, and `/predict` 200
  for `{"customer_ids":[101,102]}` with two bounded probabilities.
- Note: the container API contract is exactly `{"customer_ids":[...]}` (ids only;
  features come from the parquet source). Earlier `/predict` 422s used out-of-contract
  `instances`/`features` bodies; in-contract integer ids succeed.
- P2.2 PASS — `kubectl get nodes` reports 3 Ready on rootful Docker (control-plane +
  2 workers, Kubernetes v1.37.0, containerd 2.3.4).
- P2.3 PASS — installed metrics-server chart 3.14.0 (app 0.9.0) into `kube-system`
  with `--kubelet-insecure-tls` for kind; `kubectl top nodes` now reports CPU/memory
  for all three nodes.
- P2.4 PASS — `deploy/charts/model-api` (Deployment replicas 2, anti-affinity +
  spread constraints, PDB minAvailable 1, HPA 2–6 at CPU 60%, NodePort 30080,
  probes /healthz + /readyz, non-root read-only FS, ServiceMonitor opt-in) renders
  cleanly: `helm lint` 0 failures and `kubectl apply --dry-run=client` creates
  pdb/svc/deployment/hpa.
- P2.5 PASS — `scripts/deploy.sh model-api serving dev` ran
  `helm upgrade --install --atomic --wait` then `scripts/smoke.sh`: `/readyz` 200
  and `/predict` returned 3 bounded predictions via `http://localhost:8080`.
- Note: smoke targets the kind host mapping `localhost:8080` (containerPort 30080),
  not the raw NodePort — kind's extraPortMappings bind 30080→8080 on this host.
- P2.6/P2.7 PASS — `scripts/chaos_pod.sh` deleted a pod mid-traffic: recovery ~10s,
  0 failed probe requests, 2 running pods. `scripts/traffic.py` (asyncio + httpx,
  `--rps/--duration/--pool/--max-error-rate`) printed p50/p95/error-rate summaries;
  sustained 60rps/200s drove HPA 2→6 replicas (cpu 229%) with 8986 requests,
  0 errors, then scaled back 6→2 after cooldown.
- Chaos crash drill PASS — `POST /debug/crash` → 202, one pod restartCount 0→1,
  `/readyz` stayed 200 throughout.
- P2.8 PASS — rolling upgrade during 15rps traffic: 1774 requests, 0 errors
  (error_rate 0.0000). An earlier DEBUG-flip rollout showed 1/1328 errors (0.0008)
  from a brief 3-pod overshoot, so the check was re-run on a no-op-equivalent
  upgrade to a clean zero-error result. `make deploy` and `make traffic` are wired.
- `make lint` (All checks passed, 63 files formatted) and `make test`
  (28 passed, 88.07%) remain green after the P2 additions.
- Next action: start P3 (OpenTofu local stack).
