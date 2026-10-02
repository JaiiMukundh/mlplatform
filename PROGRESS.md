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
