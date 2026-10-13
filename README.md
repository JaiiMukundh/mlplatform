# MLPlatform

A credit-risk model platform with live serving, feature storage, model versioning,
monitoring, drift detection, and autonomous retraining. The local system proved
functionality; Azure is the deployment destination, driven by GitHub Actions.

**Current status:** GitHub-hosted CI verified. Azure deployment is next.
The dashboard is still in the local test harness; cloud hosting is the next step.

## Repository

| Directory | Responsibility |
|---|---|
| `core/` | Model API, data/training, shared code, Feast, drift monitor, retraining, remediation |
| `infra/` | Local/Azure Terraform, Helm charts, one Dockerfile with six image targets |
| `ops/` | Dashboard, demo scripts, one Azure operations script, documentation |
| `tests/` | Application tests, feature parity, release safeguards, cloud configuration contracts |
| `.github/workflows/` | Two GitHub-hosted workflows: CI and Azure operations |

Each Terraform module lives in one file. Training and release scripts are shared
between local testing and AKS. Runtime images contain no baked-in models or data.

## GitHub and Azure

Pushes and pull requests run CI on GitHub-hosted Linux runners. Cloud operations
are selected manually in **Actions → azure → Run workflow**. `plan` is read-only;
`deploy`, `wake`, and `destroy` require explicit confirmation. Deployment requires
successful CI for the selected commit and Azure OIDC/backend variables.

See [the Azure setup and operations guide](ops/docs/azure-port.md). No self-hosted
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
| `make azure ACTION=plan` | Plan using the persistent cloud backend |

## Local functionality test harness

The local environment is optional and remains available for functional testing.
Its operation is independent of the deployed Azure application.

| Target | Purpose |
|---|---|
| `make bootstrap` | Check local prerequisites |
| `make up` | Create local Kubernetes and infrastructure |
| `make deploy-all` | Seed features, train, and deploy local workloads |
| `make ui` | Open the dashboard service on port 8050 |
| `make e2e` | Verify serving and both self-healing flows |
| `make reset-demo` | Restore the repeatable baseline |
| `make demo-infra` | Inject latency and observe remediation |
| `make demo-model` | Inject drift and observe autonomous retraining/release |
| `make down` | Remove local infrastructure |

Local access: dashboard :8050, model API :8080, Grafana :3000, MLflow :5000,
MinIO :9001, Prometheus :9090. Cloud endpoints are documented after rollout.

## Evidence and explanations

- [Tasks](TASKS.md) and [real verification evidence](PROGRESS.md).
- [Architecture](ops/docs/architecture.md), [code map](CODEBASE_MAP.md),
  [operations runbook](ops/docs/runbook.md), and [demo guide](ops/docs/demo/DEMO.md).
- [Plain-English system explanation](ops/docs/ML_PLATFORM_EXPLAINED_FOR_HUMANS.md).
- [Decisions](ops/docs/DECISIONS.md) and [exact versions](ops/docs/VERSIONS.md).

The data comes from the official UCI Taiwan Credit Card Default dataset. Snapshot
dates and injected drift are simulated for the demo. Default payment next month
is mapped to the historic `default_next_90d` field; it is not a measured 90-day
outcome. Parity tests use synthetic encoding fixtures plus captured Feast bytes.

Credentials and generated datasets/models stay out of Git. Terraform state and
plan files are sensitive and ignored. Production authentication, TLS, and the
managed storage cutover are subsequent work; this repository is a functional demo.
