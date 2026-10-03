# MLPlatform

An open-source-first, laptop-hosted MLOps platform with reproducible model serving,
Kubernetes self-healing, observability, feature parity, model release gates, and an
automated drift/retraining loop. AWS is a later, explicitly human-authorized port.

The executable specification is [`docs/SPEC.md`](docs/SPEC.md). Progress is tracked
truthfully in [`PROGRESS.md`](PROGRESS.md), and `make help` is the supported command
interface.

## Current status

Local infrastructure, serving, and observability are implemented. Feature-store integration
and the later release/retraining phases are in progress; `TASKS.md` records verified status.

Feast setup uses `make feast-apply`, `make feast-materialize`, and `make feast-verify`.
The jobs render credentials from Kubernetes Secrets and use MinIO for offline Parquet,
Postgres for the registry, and Redis for online features. `make seed-data` creates
the synthetic source data; `make publish-feast-data` uploads it.

## Repository layout

A flat, single-project mono-repo: one `pyproject.toml`, one top-level package per Python
import root, one `tests/` tree, and one `docker/` directory.

| Path | Purpose |
|---|---|
| `mlp_common/` | Shared logging, configuration, schemas, drift math, S3 helpers |
| `ml/` | Synthetic data generation, training, evaluation |
| `model_api/` | FastAPI serving service and providers |
| `drift_monitor/` · `retrain/` · `remediator/` | Closed-loop services (added in later phases) |
| `docker/` | One container image definition per service |
| `feature_repo/` · `deploy/` · `infra/` | Feast repo, Helm charts, OpenTofu (created in their phases) |
| `scripts/` · `tests/` · `docs/` | Entrypoint scripts, test suite, documentation |

`make help` is the supported command interface.

## Contribution workflow

Create `feat/<phase>-<topic>` branches from `main`, use Conventional Commits, and
open pull requests with the repository template. See
[`docs/git-workflow.md`](docs/git-workflow.md).
