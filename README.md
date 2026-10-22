# MLPlatform

MLPlatform is a cloud hosted credit risk MLOps demonstration. Azure Kubernetes Service (AKS) runs the API, dashboard, data services, model jobs and monitoring stack. Terraform defines both Azure infrastructure and Kubernetes workloads. GitHub Actions builds the images, validates changes and runs confirmed cloud operations with Azure OIDC.

The repository does not provide a local application deployment. To start the cloud app, dispatch the Azure workflow from GitHub or with the GitHub CLI.

## Start the cloud app

From a clone with GitHub CLI authenticated to this repository:

```bash
gh workflow run cd.yml --ref main \
  -f action=deploy \
  -f confirmation=DEPLOY
gh run watch --exit-status
```

This sends a deployment request to GitHub. The app runs on AKS; the command does not run the app on your computer. When the workflow finishes, its run summary shows the model API and dashboard addresses.

The repository’s `azure` GitHub Environment must already have its Azure variables and OIDC identity configured. For a new Azure subscription, an administrator can run `make azure-connect` while signed in with Azure CLI and GitHub CLI. That one-time setup creates the GitHub deployment identity and repository variables; it does not create the application cluster. Azure deployments require the `DEPLOY` confirmation and a successful CI run for the exact commit.

The model API requires a bearer token for prediction and model information routes. After connecting `kubectl` to the AKS cluster, retrieve it without printing it in the terminal and call the API:

```bash
export MODEL_API_TOKEN="$(kubectl -n serving get secret model-api-token -o jsonpath='{.data.token}' | base64 -d)"
curl -H "Authorization: Bearer ${MODEL_API_TOKEN}" http://<model-api-address>:8080/model-info
unset MODEL_API_TOKEN
```

To stop and delete the project’s Azure app, AKS cluster and Terraform state, run:

```bash
gh workflow run cd.yml --ref main \
  -f action=kill \
  -f confirmation=KILL
gh run watch --exit-status
```

Deletion removes the project’s model and data history too. The GitHub OIDC identity is separate from the application resource groups and remains available for a future deployment.

## What the platform does

1. Prepares historical credit card data and trains a model.
2. Registers model artifacts and versions in MLflow, with artifacts stored in MinIO.
3. Serves predictions from FastAPI using online features from Feast and Redis.
4. Writes prediction records to PostgreSQL asynchronously so database work does not block the response.
5. Monitors feature drift and can schedule retraining jobs. A candidate model passes an evaluation gate before release.
6. Shows system health and model operations in an authenticated dashboard.
7. Collects metrics, alerts and logs with Prometheus, Alertmanager, Grafana, Loki and Alloy; a bounded remediator can handle selected conditions.

This is an engineering demonstration, not a validated lending product. It uses the UCI Taiwan Credit Card Default dataset. Snapshot timelines and injected drift are simulated. The project does not claim production credit performance, fairness, latency or availability results.

## Architecture

```mermaid
flowchart TB
    subgraph Delivery[Source and cloud delivery]
        Code[Reviewed change] --> CI[GitHub CI<br/>quality and security]
        CI --> Images[Build and scan seven image targets]
        OIDC[GitHub OIDC identity] --> Dispatch[Confirmed Azure workflow]
        Dispatch --> TFCloud[Azure Terraform root]
        Images --> ACR[Azure Container Registry]
        TFCloud --> AKS[Azure Kubernetes Service]
        TFWorkloads[AKS Terraform root<br/>bootstrap, platform, app] --> AKS
        ACR --> AKS
    end

    subgraph Runtime[Azure cloud runtime]
        LB[Azure load balancer] --> API[FastAPI model API]
        LB --> UI[Operations dashboard]
        API --> Feast[Feast and Redis]
        API --> MLflow[MLflow registry]
        API -. queued prediction logs .-> PG[PostgreSQL]
        MinIO[MinIO artifact and offline store] --> MLflow
        MinIO --> Train[Training and retraining Jobs]
        Feast --> Train
        Train --> MLflow
        PG --> Drift[Drift monitor]
        MLflow --> Gate[Candidate evaluation gate]
        Drift --> Train
        Gate --> API
        Metrics[Prometheus and Alertmanager] --> Remediator[Remediator]
        Remediator --> API
        Logs[Loki and Alloy] --> UI
        Metrics --> UI
    end
```

### Prediction request

```mermaid
sequenceDiagram
    participant Client
    participant LB as Azure load balancer
    participant API as Model API on AKS
    participant Feast as Feast / Redis
    participant Model as MLflow model
    participant Queue as Bounded log queue
    participant DB as PostgreSQL
    Client->>LB: Prediction request
    LB->>API: Route to healthy pod
    API->>Feast: Read online features
    Feast-->>API: Feature vector
    API->>Model: Score request
    Model-->>API: Risk probability and version
    API->>Queue: Enqueue prediction record
    API-->>Client: Prediction and request ID
    Queue-->>DB: Persist asynchronously
```

An accepted prediction can return before its database record is written. The queue has a fixed capacity; a full queue or final flush failure can drop records and is surfaced through logs and metrics.

### Deployment order

```mermaid
flowchart LR
    A[GitHub-hosted runner] --> B[Azure Terraform]
    B --> C[Network, AKS, ACR, public IP]
    C --> D[AKS bootstrap: namespaces and CRDs]
    D --> E[Platform: data and observability]
    E --> F[Initial data and model]
    F --> G[App: API, dashboard, jobs]
    G --> H[Smoke and health checks]
    H --> I[Timed cleanup or confirmed teardown]
```

`infra/envs/azure` manages Azure resources. `infra/envs/aks` manages Kubernetes resources through Terraform’s Kubernetes provider. Staged applies allow the cluster, namespaces, CRDs, data services and application to become available in dependency order. The cloud workflow runs on a GitHub-hosted runner, uses OIDC for Azure access and checks successful CI for the exact commit before deployment.

## CI/CD workflows

The workflow definitions are in [`.github/workflows/`](.github/workflows/):

| Workflow | File | When it runs | What it does |
|---|---|---|---|
| `ci` | [`ci.yml`](.github/workflows/ci.yml) | Pull requests and pushes to `main` | Lint and test Python; validate Terraform, actions and Kubernetes manifests; scan secrets and dependencies; build and smoke test all seven Docker targets. |
| `azure` | [`cd.yml`](.github/workflows/cd.yml) | Manual dispatch from `main`; model release dispatch | Plan, deploy, verify, update dashboard access, release a candidate, sleep, wake, destroy or fully delete the Azure environment. Billable/destructive operations require an explicit confirmation. |
| `azure-expiry` | [`expiry.yml`](.github/workflows/expiry.yml) | Scheduled check every 15 minutes | Deletes an expired test deployment and verifies the application and Terraform-state groups are gone. |

## Alert quick checks

These are first checks for the alerts configured in Prometheus. Inspect the AKS workload and logs through the authenticated dashboard or the Azure workflow runner.

### Model API down

Check the `serving` deployment and pod logs, then verify Redis, MLflow and PostgreSQL in `data`. If the outage followed a release, use the rollback procedure in `scripts/model_release.sh`.

### Pod crash looping

Inspect the container’s termination reason, readiness failures and memory limits. Confirm the selected model exists in MLflow and the Feast online store responds.

### High error rate

Check prediction response codes and model API logs. Confirm feature hydration in Redis and the champion alias in MLflow before rolling back a recent release.

### High p95 latency

Inspect API pod resources, HPA status, Prometheus request latency and dependency latency. The remediator can raise the HPA minimum replica count.

### Model drift detected

Check the drift window size, consecutive breaches, cooldown, MLflow reference artifact and retraining Job. Demo drift injection is simulated.

### Retrain failed

Inspect the retraining Job and its Feast and MLflow dependencies. A candidate must pass the release gate before promotion; the current champion should remain serving while the failure is resolved.

## Run checks

These commands check source and infrastructure definitions. They do not deploy or start the application:

```bash
uv sync --frozen --all-groups
make lint test
make check-infra check-actions check-manifests
make secret-scan security
```

`make check-images` builds and smoke tests the Docker image targets and uses local Docker as a build tool. It does not launch the MLPlatform application. No local app server or local cluster is part of the deployment path.

## Why `uv.lock` is here

[`uv.lock`](uv.lock) records exact versions and hashes for the Python dependency graph, including indirect dependencies. CI and the Azure workflow use `uv sync --frozen`, so the same reviewed dependency set is installed each time. The file is about 236 KB in the current checkout; removing it would make builds less reproducible, so it is intentionally checked in.

## Technology at a glance

| Capability | Included |
|---|---|
| Kubernetes | Yes — AKS runs and orchestrates the application workloads. |
| Load balancing | Yes — Kubernetes `LoadBalancer` services use Azure load balancing and a Terraform-managed public IP. |
| Orchestration | Yes — Kubernetes schedules containers, health checks, rollouts and Jobs; Terraform provisions infrastructure in stages. |
| Dockerfiles | Yes — one multi-stage [`infra/Dockerfile`](infra/Dockerfile) defines seven image targets. |
| Helm | No — Azure and Kubernetes deployment definitions are Terraform. |

## Repository map

| Path | Purpose |
|---|---|
| `core/model_api/` | FastAPI prediction service and request logging |
| `core/ml/`, `core/feature_repo/` | Feature preparation, training, evaluation and Feast definitions |
| `core/drift_monitor/`, `core/retrain/`, `core/remediator/` | Drift detection, retraining and bounded remediation |
| `ui/` | Operations dashboard served from AKS |
| `infra/envs/azure/` | Azure infrastructure Terraform root |
| `infra/envs/aks/` | Kubernetes workload Terraform root |
| `infra/manifests/`, `infra/jobs/` | Terraform inputs and Kubernetes Job definitions |
| `infra/Dockerfile` | Multi-stage image definitions |
| `scripts/` | Cloud workflow, validation, release and smoke-check helpers |
| `.github/workflows/` | CI, Azure operations and expiry cleanup |
| `tests/` | Unit tests and cloud configuration checks |
