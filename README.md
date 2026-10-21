# MLPlatform

A credit-risk model platform with live serving, feature storage, model versioning,
monitoring, drift detection, and autonomous retraining. The runtime deployment is Azure Kubernetes Service, driven by GitHub Actions.

**Current status:** Cloud deployment preparation verified. Azure rollout is in progress.
The dashboard has an AKS image with HTTPS/login and in-cluster operations.

## Repository

| Directory | Responsibility |
|---|---|
| `core/` | Model API, data/training, shared code, Feast, drift monitor, retraining, remediation |
| `infra/` | Azure Terraform, cloud Helm charts, one Dockerfile with seven image targets |
| `scripts/` | Cloud operations, data preparation, and demo tools |
| `ui/` | Operations dashboard |
| `docs/` | Specification, decisions, explanations, runbooks, and measured evidence |
| `tests/` | Application tests, feature parity, release safeguards, cloud configuration contracts |
| `.github/workflows/` | GitHub-hosted CI, Azure operations, and test-session expiry |

Charts live directly in `infra/charts/`, jobs in `infra/jobs/`, and the shared
Dockerfile at `infra/Dockerfile`. There are no archived documentation folders.
Each Terraform module lives in one file. Training and release scripts run against AKS. Runtime images contain no baked-in models or data.

## GitHub and Azure

Pushes and pull requests run CI on GitHub-hosted Linux runners. Cloud operations
are selected manually in **Actions → azure → Run workflow**. `plan` is read-only;
`deploy`, `wake`, and `destroy` require explicit confirmation. Deployment requires
successful CI for the selected commit and Azure OIDC/backend variables.

See [the Azure setup and operations guide](docs/azure-port.md). No self-hosted
laptop runner is needed. No Azure deployment has been performed by the agent.

## Make is the interface

| Target | Purpose |
|---|---|
| `make help` | List supported commands |
| `make tools` | Install checksum-verified Linux CI tools |
| `make lint test` | Python quality checks and coverage gate |
| `make check-infra` | Terraform validation, Helm lint, shell syntax |
| `make check-actions check-charts` | Workflow lint and strict Kubernetes/CRD schema validation |
| `make check-images` | Build and import-smoke all six service images |
| `make secret-scan security` | Credential and dependency scans; report infrastructure findings |
| `make github-login` | Authenticate GitHub CLI and Git |
| `make github-push` | Publish the current branch without force |
| `make azure-connect` | Configure free GitHub OIDC identity and Azure variables |
| `make azure ACTION=plan` | Plan using the persistent cloud backend |
| `make azure-kill CONFIRMATION=KILL` | Delete all project Azure resources, including state storage |

## Local development tools

`make lint test check-infra check-actions check-charts check-images secret-scan`
checks code and cloud configuration without deploying a local cluster.
`make seed-data` prepares the demo dataset for upload to the cloud. The local
kind cluster, registry, Terraform environment, and `make up/down` deployment
targets have been removed. The application runs on AKS when deployed.

## Evidence and explanations

- [Tasks](TASKS.md) and [real verification evidence](PROGRESS.md).
- [Architecture](docs/architecture.md),
  [operations runbook](docs/runbook.md), and [demo guide](docs/DEMO.md).
- [Plain-English system explanation](docs/ML_PLATFORM_EXPLAINED_FOR_HUMANS.md).
- [Decisions](docs/DECISIONS.md) and [exact versions](docs/VERSIONS.md).

The data comes from the official UCI Taiwan Credit Card Default dataset. Snapshot
dates and injected drift are simulated for the demo. Default payment next month
is mapped to the historic `default_next_90d` field; it is not a measured 90-day
outcome. Parity tests use synthetic encoding fixtures plus captured Feast bytes.

Credentials and generated datasets/models stay out of Git. Terraform state and
plan files are sensitive and ignored. Production authentication, TLS, and the
cloud dashboard hosting are subsequent work; this repository is a functional demo.

Files beginning with a dot are tool configuration, not discarded app code:
`.github/` runs Actions, `.gitignore` excludes secrets/generated output,
`.dockerignore` controls image contents, `.python-version` pins Python, and
`.pre-commit-config.yaml` runs optional local checks. `.env.example` is the
credential template. `.git/` stores repository history; `.venv/`, `.terraform/`,
and cache directories are generated locally and are not published to GitHub.

For a full cost shutdown, use the GitHub **azure** workflow with action **kill**
and confirmation **KILL**. The two-hour expiry workflow is a backup, checked
every 15 minutes; GitHub scheduling can run late. Full kill deletes test data
and model history as well as compute, disks, images, and state storage.

If the CI runner Docker bridge cannot download pinned build dependencies,
`make check-images DOCKER_NETWORK=host` runs the same checks using host networking.
Cloud workflows use their GitHub runner network.
