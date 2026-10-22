# Architecture decisions

## 2026-10-21 — Azure infrastructure and AKS workloads in Terraform

Two Terraform roots separate Azure provisioning from Kubernetes resources. The AKS root applies custom resource definitions and credentials first, then platform services, then the application after initial model training. This preserves the dependency order while keeping Terraform as the source of deployment state. Cloud model releases patch the Terraform-created deployments and are reconciled by the next full deployment.

## 2026-10-21 — Cloud-only runtime

AKS is the application runtime. GitHub-hosted runners perform CI, image builds, data seeding, and selected cloud operations. API serving uses MLflow models and Feast online features. Cloud training uses Feast historical retrieval. Hermetic tests exercise code and deployment contracts without hosting the application.

## 2026-10-21 — Secrets and cost controls

The AKS Terraform root generates credentials and the test dashboard certificate; the remote state is sensitive. Azure operations use OIDC, explicit confirmations, project ownership checks, and test-session expiry. A new billable deployment requires authorization for that operation.
