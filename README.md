# MLPlatform

An open-source-first, laptop-hosted MLOps platform with reproducible model serving,
Kubernetes self-healing, observability, feature parity, model release gates, and an
automated drift/retraining loop. AWS is a later, explicitly human-authorized port.

The executable specification is [`docs/SPEC.md`](docs/SPEC.md). Progress is tracked
truthfully in [`PROGRESS.md`](PROGRESS.md), and `make help` is the supported command
interface.

## Current status

Foundation work is in progress. Run `make help` to see implemented and planned targets.

## Contribution workflow

Create `feat/<phase>-<topic>` branches from `main`, use Conventional Commits, and
open pull requests with the repository template. See
[`docs/git-workflow.md`](docs/git-workflow.md).
