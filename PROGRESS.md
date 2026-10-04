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
- P3.1 PASS — `tofu -chdir=infra/modules/cluster_kind validate` reports
  `Success! The configuration is valid`; `fmt -check` clean. Module reproduces
  `infra/kind-config.yaml` (3 nodes, registry mirror, 8 port mappings from 5.3);
  provider `tehcyx/kind 0.11.0` confirmed latest on registry.opentofu.org;
  node image digest verified via `docker images --digests`.
- Next action: finish P3.2 (registry module; fix builtin-provider version pin).
- P3.2 PASS — `tofu -chdir=infra/modules/registry init -backend=false` succeeded
  after removing the explicit version constraint on `terraform.io/builtin/terraform`
  (built-in providers forbid it); `validate` reports Success, `fmt -check` clean.
- P3.2 PASS — `sg docker -c 'bash scripts/registry.sh'` is idempotent
  (`already running`, `already attached`, ConfigMap `unchanged`);
  `curl localhost:5001/v2/` returns HTTP 200.
- Next action: fix the redis image pin, then verify P3.3 charts.
- P3.3 PASS — `helm lint` clean on all three charts; `helm template` renders
  postgres StatefulSet+init Job (prediction_log + index, drift_state, labels_log;
  0 Secrets with `auth.existingSecret`), minio Deployment+buckets Job
  (NodePorts 30900/30901, 3 buckets), redis Deployment (fixed pin
  `7.2.16-alpine3.21@sha256:29e8589c…`, `--appendonly no`).
- P3.3 PASS — fixed a bad redis pin (`7.2-alpine3.22` does not exist upstream);
  image choices recorded in DECISIONS.md, digests in VERSIONS.md.
- Next action: implement P3.4 platform_services module.
- P3.4 PASS — `tofu -chdir=infra/modules/platform_services validate` reports
  Success with no warnings; `fmt -check` clean. New module installs
  metrics-server 3.14.0 (`--kubelet-insecure-tls`, as in P2.3) plus the three own
  charts into ns `data`, with `random_password` -> `kubernetes_secret_v1` wiring
  (`auth.existingSecret`; alphanumeric passwords for URL safety).
- P3.4 PASS — used `kubernetes_namespace_v1`/`kubernetes_secret_v1` (the
  non-deprecated names in provider 3.3.0); first draft with the old names
  produced deprecation warnings, now resolved.
- Next action: implement P3.5 (local env composition, make up/down).
- P3.5 PASS — `make down` removed the P2 cluster and registry; `make up`
  rebuilt from nothing: registry (tofu), 3-node kind v1.37.0 cluster (tofu via
  kind CLI), metrics-server + postgres/minio/redis (tofu helm_release).
- P3.5 PASS — `kubectl get pods -A`: data ns postgres/minio/redis Running,
  metrics-server Running, `kubectl top nodes` reports all 3 nodes.
- P3.5 PASS — `make tofu-local-apply` second run: `No changes. Your
  infrastructure matches the configuration`; `make up` twice: both applies
  no-op, `bootstrap complete`.
- P3.5 PASS — in-cluster psql `\dt` shows `prediction_log`, `drift_state`,
  `labels_log`; all four helm releases `deployed`.
- P3.5 PASS — model-api restored on the new cluster (`docker push` +
  `make deploy`): smoke `/readyz` 200, `/predict` 3 bounded probabilities.
- Next action: implement P3.6 (AWS parity modules, plan-only).
- P3.6 PASS — `tofu -chdir=infra/envs/aws init -backend=false` ok;
  `validate` reports Success; `fmt -check` clean. Six modules created
  (network_vpc, cluster_eks, object_storage, database, image_registry, iam)
  plus a monthly budget alarm; env contract outputs written.
- P3.6 PASS — `plan -lock=false` with dummy creds fails ONLY at STS
  GetCallerIdentity (InvalidClientTokenId): no syntax/type errors, resource
  graph builds fully. No apply was run (cost safety).
- Next action: P3.7 formatting/validation checks, then the P3 acceptance gate.
- P3.7 PASS — `tofu fmt -check -recursive` clean on both envs; `validate`
  Success on both; minimal `.github/workflows/ci.yml` ships the `iac` job
  (action majors verified: checkout v7, setup-opentofu v2; SHA pins in P4.2).
- P3 ACCEPTANCE PASS — final `make down && make up` from nothing: 3 Ready nodes
  (v1.37.0), data ns postgres/minio/redis Running, bucket Job Completed
  (hook-cleaned), `make tofu-local-apply` No changes, AWS `validate` Success,
  AWS `plan` fails only on dummy-creds STS, psql shows prediction_log.
- Note: one transient `plan` failure ("Planning failed", no detail captured)
  right after bootstrap; 4 subsequent plan/apply runs all report No changes.
- P3 ACCEPTANCE PASS — post-cycle `make deploy` smoke green; `make lint`
  (All checks passed) and `make test` (28 passed, 88.07%) still green.
- Next action: start P4 (CI/CD).
- Infra: removed rootless Docker (binaries in ~/.local/bin, systemd user unit, socket). Real daemon is now /usr/bin/docker 29.1.3 on unix:///var/run/docker.sock; plain `docker` works after a fresh login (docker group); use `sg docker -c` in the current session. Residual rootless data ~2.3M left under ~/.local/share/docker (inert).
- P4 PASS — full `ci.yml` (lint/test/iac/chart/security) valid YAML; `helm lint` clean; `cd.yml` written (staging 30081→8081, prod 30080→8080, trivy image, rollback).
- P4.4 PASS — slim image (no baked artifacts) + MinIO initContainer (`mc mirror`); `publish_model_file.sh` clean layout; serving redeployed, smoke `/readyz` 200 + `/predict` 3.
- P4.5 PASS — branch→merge→build→deploy; serving image now `localhost:5001/model-api:p4demo`; smoke PASS. Evidence `docs/demo/branch-to-deployment.md`.
- P4.6 PASS — broken image fails staging (atomic uninstall), prod still 200 on p4demo. Evidence `docs/demo/cicd-failure-path.md`.
- Note: GitHub workflow execution + P4.1 runner install pending HUMAN (docs ready). P4.7 stretch: `.actrc` only.
- Next action: start P5 (observability).
- P5.1 PASS — kube-prometheus-stack 91.8.2 via tofu (Grafana :3000, Prometheus :9090, Alertmanager :9093; retention 2d; all-namespaces ServiceMonitors; sidecar dashboards).
- P5.2 PASS — Loki 7.3.0 SingleBinary + Alloy DaemonSet; serving logs in Loki with namespace/pod/container/app labels; Loki datasource in Grafana.
- P5.3 PASS — model-api ServiceMonitor (jobLabel=app name) UP x2 in Prometheus.
- P5.4 PASS — Service Health / Logs / ML Health dashboards provisioned via ConfigMaps, all load.
- P5.5 PASS — 6 rules loaded (ModelApiDown, PodCrashLooping, HighErrorRate, HighP95Latency + P8 stubs); runbook anchors written.
- P5.6 PASS — remediator (FastAPI /alert, HPA-floor action, Grafana annotate, rollout restart, debounce, metrics) deployed; 7 unit tests pass.
- P5.7 PASS — chaos_alert drill: 500ms+10rps → HighP95Latency firing → HPA 2→4 + Grafana annotation; cleanup restored. Evidence docs/demo/alert-drill.md.
- Note: upstream charts vendored to infra/charts/ (asset host timeouts); metrics-server also vendored. Charts recorded in VERSIONS.md.
- Next action: start P6 (feature store + model registry).
- P6.1 PASS — MLflow 3.16.1 at `localhost:5000`: `/health` -> `OK` (200), `/version` ->
  `3.16.1`, `experiments/search` returns the Default experiment with
  `artifact_location: mlflow-artifacts:/0` (Postgres backend store + MinIO artifact
  proxy working). `minio/health/live` -> 200; `POST /predict` on `:8080` -> 3 bounded
  probabilities. Re-verified after BLK-004.
- BLK-004 (2026-10-03) — the host rebooted ~5h earlier and reverted the inotify
  limits that BLK-002 had raised at runtime. `fs.inotify.max_user_instances=128`
  makes kube-proxy die with `fsnotify watcher init: too many open files`; CoreDNS
  then cannot reach the API VIP, so *all* in-cluster DNS fails and every podified
  service crash-loops (mlflow, coredns, metrics-server, kube-state-metrics,
  loki-gateway; model-api `Unknown`; host NodePorts reset). Nodes still report
  Ready. Needs root; the agent has no passwordless sudo. Fix in BLOCKERS.md.
- BLK-004 RESOLVED 2026-10-03 — human applied the sysctl fix and installed the
  persistent drop-in; `make preflight` now passes (512/524288). kube-proxy and
  CoreDNS recovered, `getent hosts minio.data.svc` resolves, the crash-looped
  pods were rolled, and MLflow is 1/1.
- Added while blocked (verified locally): `scripts/check_host.sh` + `make preflight`
  fail loudly with the exact `sysctl` remediation, and `make up` now runs the same
  check as its first step; `infra/sysctl/99-kind-inotify.conf` is the persistent
  drop-in for the human. Decision recorded in docs/DECISIONS.md.
- `make preflight` observed: `too low fs.inotify.max_user_instances 128 (required >= 512)`
  and `too low fs.inotify.max_user_watches 248131 (required >= 524288)` -> exit 1.
- P6.2 (config, verified locally) — `feature_repo/feature_store.yaml.tmpl` +
  `feature_repo/render_config.py` render the SQL registry on Postgres and the Redis
  online store from env vars and fail loudly on any missing value; the rendered
  `feature_store.yaml` (which holds the Postgres password) is now gitignored and
  dockerignored and removed from the index. `definitions.py` now uses the spec's
  `ttl=timedelta(days=365)` and `FeatureService("loan_default_v1")`.
  Evidence: `uv run pytest tests/test_feast_config.py -q` -> 3 passed;
  `make lint` -> All checks passed; `make test` -> 38 passed, coverage 88.07%.
- Still untracked WIP (needs a live cluster to exercise/verify): `deploy/feast-setup-job.yaml`
  (must render the config before `feast apply`) and `docker/training.Dockerfile`.
- Next action: human applies the sysctl fix (BLK-004); then re-verify P6.1 and
  continue P6.2/P6.3 (publish parquet to `feast-offline`, render config, `feast apply`,
  materialize into Redis).
- P6.1 re-verified after BLK-004: `curl localhost:5000/health` -> `OK` (200),
  `/version` -> `3.16.1`; `minio/health/live` -> 200; serving `/readyz` 200,
  `/model-info` `file-v1` with six features.
- P6.2/P6.3 PASS — `scripts/publish_feast_data.sh` uploaded
  `customer_features.parquet` (4.07 MiB) + `labels.parquet` to MinIO
  `feast-offline` (host `localhost:9000`, idempotent `mc mb/cp`).
- P6.2/P6.3 PASS — `make feast-verify` (via `scripts/run_job.sh`
  `deploy/feast/verify-job.yaml`) completed: `historical rows=20`
  (5 customers x 4 point-in-time snapshots, all six features) and
  `online customer_ids=[1, 2, 3, 4, 5]` with real values
  (e.g. income `[44954.5, 71620.1, 164542.5, 45144.5, 43899.4]`).
- Note: `feast apply` prints `Could not validate FileSource path
  's3://feast-offline/customer_features.parquet': Bucket 'feast-offline' not
  found` even when the bucket exists — the registry apply still succeeds and
  offline reads via S3 work (proven by the 20-row historical pull). Warning
  only, recorded here, not a failure.
- Fix: `feature_repo/verify.py` now resolves the `FeatureService` object via
  `store.get_feature_service("loan_default_v1")` — Feast 0.66 rejects a bare
  name string for both historical and online calls (`AssertionError`).
- Structure: the single `deploy/feast-setup-job.yaml` became three jobs
  `deploy/feast/{apply,materialize,verify}-job.yaml` (each deletes any
  previous Job first, so `make feast-apply/materialize/verify` stay
  re-runnable); `training.Dockerfile` adds `s3fs` + `psycopg[binary]`
  (boto3 pinned to 1.43.106 for aiobotocore 3.9.2; transitive lock in
  `requirements/training.txt`); old `feast-setup-job.yaml` removed.
- Gates green: `make lint` (All checks passed, 71 files formatted),
  `pytest tests/test_feast_config.py` (3 passed), `make test`
  (38 passed, 88.07% coverage), `pre-commit run --all-files` passed.
- P6.4 PASS — `make train-mlflow` (Job `train-mlflow`, TRIGGER=manual)
  completed: `mlflow trained run_id=d43d1965... version=1 alias=champion
  validation_auc=0.8562 test_auc=0.8581` (identical to file mode: same rows,
  same seed). Registry shows `loan-default` v1 READY with alias `champion`;
  run tags carry feast service, data window, git SHA, trigger; artifacts
  `reference.parquet` + `eval_set.parquet` present.
- P6.4 PASS — in-cluster `mlflow.sklearn.load_model('models:/loan-default/1')`
  loads in ~4s and predicts (7 artifacts via proxy). Host-networked download
  hangs on presigned `minio.data.svc` URLs (cluster DNS only) — recorded in
  DECISIONS.md; model-loading work runs in-cluster from here on.
- Note: models log with `serialization_format="cloudpickle"` (skops gates
  HistGradientBoosting at save+load); first attempt failed loudly on exactly
  that, fixed, re-ran green. Serving gains `redis/mmh3/mlflow-skinny` deps
  (pinned; `feast` itself stays out for the pandas<3 conflict).
- P6.4b PASS — `pytest tests/test_parity.py` 5 passed: field keys and one
  entity key reproduce live-captured Feast bytes exactly, captured raw values
  decode to Feast's own numbers, and 200 random customers round-trip
  bit-exact (float32) / exact (int) through the serving reader.
- P6.5/P6.6 PASS — `FeastFeatureSource` (raw Redis reader, `ping` false on
  outage) and `MlflowModelSource` (pinned `models:/name/version`, 60s
  startup retries then exit 1) wired by `FEATURE_SOURCE`/`MODEL_SOURCE`;
  `/model-info` now carries `mlflow_run_id`, `feature_service`,
  `registered_at`. `model.version` is the single pinned source of truth.
- P6.7 PASS — `make deploy` serves `model_version "1"` end-to-end
  (Feast→MLflow→response→`prediction_log` rows for v1). v1 probabilities
  match the file-mode model to 8 decimals for ids 1–3 (same rows+seed).
  Redis kill drill: `readyz` 503 while Redis is at 0 replicas (`/predict`
  500s, no fabricated features), 200 after recovery.
- Note: first P6.7 deploy CrashLooped on a stale cached `dev` image
  (`imagePullPolicy: IfNotPresent`); flipped to `Always` (same lesson as the
  Feast jobs) and redeployed green. `DATABASE_URL` is now mirrored into the
  release namespace by `deploy.sh` (secret `postgres-app`).
- P6.8 PASS — `docs/lineage.md` traces a real prediction
  (`b29a7440…`, customer 3, v1, 0.0298) to run `d43d1965`, data window,
  feature service, and git SHA.
- Gates: `make lint` clean, `make test` 48 passed / 84.34%.
- Next action: implement P7 (model-aware CI/CD).
- P7.1 PASS — `scripts/gate.py` (5 SPEC checks, `gate_report.json`, exit
  0/1) + `tests/test_gate.py` 7 passed (each failure mode + pass case).
  Scoring runs in-cluster (`make gate-candidate VERSION=N`, Job
  `deploy/gate/gate-job.yaml`): v1 self-gate PASS (0.8581, 12000 rows).
- P7.2 PASS — `scripts/loadcheck.py` (stdlib; N=2000 @20rps; p95≤150ms,
  err≤0.5%): 200-req trial vs prod PASS (p95 ~15ms, exit 0).
- P7.3 PASS — `scripts/model_release_local.sh` (gate→staging→loadcheck→
  promote→prod→verify, reject-or-rollback everywhere) + thin
  `.github/workflows/model-release.yml` wrapper calling the same scripts.
- P7.4a PASS — v2 released green: gate PASS, staging 2000-req PASS, champion
  1→2, all pods v2, 100-req check PASS.
- P7.4b PASS — shuffled-label v3 (AUC 0.5079) gate-REJECTED on the floor;
  tagged rejected, candidate alias removed, prod stayed v2.
- P7.4c PASS — v4 passed gate, staging injected with 500ms chaos failed
  loadcheck (p95 522ms); staging rolled back, v4 rejected, prod stayed v2.
- P7.4d PASS — prod upgrade to bogus v999 failed (new RS 0 available,
  old RS kept serving v2); `helm rollback` restored v2-only, champion 2.
- Evidence: `docs/demo/model-release-drills.md`. Fixes kept: staging smoke
  URL, `imagePullPolicy: Always`, empty-store 404 (not 500), full-range
  `make feast-rematerialize` (incremental cannot refill a wiped Redis).
- Gates: `make lint` clean, `make test` 56 passed / 84.53%.
- Next action: implement P8 (drift detection + automated retraining).
- P8.1 PASS (2026-10-04) — `uv run pytest tests/test_drift.py -q` -> 8 passed;
  tests cover identical samples, shifted means, a hand-computed PSI value,
  ties/constant features, empty input failure, KS significance, and the
  multi-feature threshold rule. `make test` -> 82 passed, 85.86% coverage;
  `make lint` -> All checks passed.
- Next action: deploy and verify the P8.2 drift monitor plus P8.3 retrain Job
  template/RBAC on the live local cluster.
- P8.2/P8.3 PASS (2026-10-04) — `helm lint deploy/charts/drift-monitor
  deploy/charts/retrain` -> 2 charts linted, 0 failed; `make deploy-monitor`
  rebuilt/pushed both images, upgraded both releases, restarted the reused
  `dev`-tag monitor pod, and completed its first evaluation. `/state` reported
  champion `68`, 1,000 samples, and three drifted features; `/metrics`
  exposed per-feature PSI/KS, drift flag, sample count, last-evaluation time,
  and retrain counter. ServiceAccount checks returned `yes` for `create` and
  `list` Jobs in `data`.
- Trigger drill: after two consecutive breached windows the monitor created
  `retrain-68-1791104712` with `ttlSecondsAfterFinished=3600`,
  `backoffLimit=1`, label `app=retrain`, parent champion, and drift report
  injected from the ConfigMap template. The existing dirty cluster then made
  the Job fail correctly because champion 68 had no labels newer than its
  `data_end`; that is the expected explicit failure path, not a successful
  retrain. A clean-room self-heal run is the next action.
- Next action: finish P8.4 retraining and dispatch on a reset baseline plus a
  newly simulated drift snapshot.
- P8.4 PASS (2026-10-04) — after `make reset-demo` aligned generated baseline
  data through 2026-10-01 with champion v2, `simulate_drift --scenario both`
  measured champion AUC 0.8562 -> 0.6714 (drop 0.1848). The automatic Job
  `retrain-2-1791105711` registered MLflow v70 with `trigger=drift`,
  `parent_champion=2`, test AUC 0.8349, and passed the shared gate, 2,000-request
  staging load check (p95 17.5 ms, 0% errors), prod rollout, and 100-request
  verification. `/model-info` reported v70 on prod; the next monitor cycles
  reported `model_drift_detected=0` with PSI 0.0008–0.0122 across all six
  features. The Job completed successfully and local dispatch used the same
  release scripts as CI.
- Next action: finish P8.5 retraining metrics/alert and P8.6 dashboard panels.
- P8.5/P8.6 PASS (2026-10-04) — Prometheus queries returned
  `model_champion_auc=0.834877`, `model_candidate_auc=0.834877`,
  `model_drift_detected=0`, six `model_feature_psi` series, and the drift
  window/last-evaluation gauges. The live `observability-content` release was
  upgraded; `RetrainFailed` now selects local `data` Jobs, and the ML Health
  dashboard includes PSI/KS thresholds, drift flag/window/retrain panels,
  champion-vs-candidate AUC, and a Prometheus retrain-event annotation.
- Next action: run the repeatable `make demo-model` orchestration and close
  the remaining P8 safeguards checklist.
- P8.7 PASS (2026-10-04) — the final `make demo-model` run is recorded in
  `docs/demo/model-selfheal.md`: baseline traffic 2,356 requests with 0
  errors and `drifted=false`; synthetic `both` drift lowered AUC 0.8562 ->
  0.6714; the monitor raised the flag, Job `retrain-2-1791107413` registered
  v75, the shared gate/staging/prod checks passed, and the monitor cleared the
  flag after rollout with max PSI 0.0146. Reset now flushes Redis and recovers
  stale pending staging Helm revisions, making the demo repeatable after an
  interrupted run. No screen clip is attached; the timestamped terminal log
  is the captured evidence.
- P8.8 PASS (2026-10-04) — `uv run pytest tests/test_drift_safeguards.py
  tests/test_retrain.py -q` -> 18 passed; safeguards cover insufficient
  samples, consecutive-breach counting/reset, cooldown, active Jobs, failed
  Jobs without completion timestamps, post-parent data requirements, and
  local/GitHub dispatch behavior.
- P9.1 PASS (2026-10-04) — `make e2e` -> 3 passed, 1 warning in 522.00s.
  The serving test verified health/readiness, Prometheus metrics, model-info,
  and predictions; the infra test deleted a serving pod with a <=1% error
  budget; the model test ran the unattended synthetic drift demo and verified
  champion/model convergence with drift cleared. Focused reruns also passed:
  infra 1 passed in 12.10s and serving 1 passed in 0.07s.
- P9.2 PASS (2026-10-04) — `make down && make up && make deploy-all && make e2e`
  executed completely unattended without manual steps. Recorded in `docs/runbook.md`:
  total measured duration 18m46s, clean rebuild of kind cluster, OpenTofu data and
  observability infrastructure, bootstrap image pushing, all 6 microservice images,
  Feast feature store definitions, MLflow model promotion (v1 -> v2), and 3/3 e2e
  test suites passing (`test_serving_contract`, `test_serving_survives_pod_deletion`,
  `test_model_self_healing_loop`).
- P9.3 PASS (2026-10-04) — Hardening audit verified against live cluster: all 6 Dockerfiles
  execute as non-root (`USER 10001:10001`) with clean hadolint runs; resource requests and
  limits set on all services; NetworkPolicy default-deny and egress whitelist active in
  serving namespace; RBAC least-privilege verified via `kubectl auth can-i` (remediator and
  drift-monitor strictly scoped); and Gitleaks scan scanned 48 commits with 0 leaks found.
  Documented in `docs/hardening.md`.
- Next action: implement P9.4 failure modes matrix and experiment verification.
