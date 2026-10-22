# Cloud-only platform specification

## Scope

Azure Kubernetes Service is the only application runtime. GitHub-hosted runners perform CI and selected cloud operations. Azure Terraform owns the resource group, network, AKS, registry, public IP, and budget. A separate AKS Terraform root manages Kubernetes namespaces, secrets, custom resource definitions, services, workloads, and observability resources. No workstation application deployment is supported.

## Required behavior

1. The model API serves an MLflow registered model using Feast online features, logs predictions asynchronously, exposes readiness and metrics, and scales in AKS.
2. A cloud training Job uses Feast historical retrieval and a temporal split, logs MLflow artifacts and evaluation, and registers a model version.
3. The release path gates candidates, deploys to staging, runs load and smoke checks, promotes the champion alias, rolls out serving, and rolls back on failure.
4. The drift monitor compares recent prediction features with the MLflow reference, applies consecutive-breach and cooldown safeguards, and creates an AKS retraining Job.
5. Retraining registers a candidate and invokes the in-cluster release path or GitHub dispatch.
6. Prometheus, Alertmanager, Grafana, Loki, Alloy, and the remediator support monitoring and incident response.
7. The AKS dashboard requires authentication and operates against cluster services.
8. GitHub CI runs lint, tests, coverage, Terraform validation, manifest validation, image checks, secret scanning, and security checks.
9. Cloud operations use explicit confirmation and ownership guards. A full kill removes only project-owned application, AKS node, and state resource groups.

## Acceptance

Run `make lint test check-infra check-actions check-manifests secret-scan` on the repository. This validates source and cloud configuration; a successful live deployment requires a separately authorized Azure run and AKS smoke checks. Data snapshots and drift injection are simulated and must be described as such.
