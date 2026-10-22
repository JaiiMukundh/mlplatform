# Cloud architecture

```mermaid
flowchart LR
  GH[GitHub Actions] --> TF[Azure Terraform]
  TF --> AKS[AKS]
  GH --> ACR[Azure Container Registry]
  ACR --> AKS
  Client --> API[Model API on AKS]
  API --> Redis[Feast online store / Redis]
  API --> MLflow[MLflow registry]
  API --> Postgres[Prediction log / PostgreSQL]
  MinIO[MinIO object store] --> MLflow
  MinIO --> Feast[Feast historical data]
  Feast --> Train[Training and retraining Jobs]
  Train --> MLflow
  Postgres --> Drift[Drift monitor]
  MLflow --> Drift
  Drift --> Train
  Train --> Release[Candidate gate and release]
  Release --> API
  Prom[Prometheus / Alertmanager] --> Rem[Remediator]
  Rem --> API
  Dashboard[AKS dashboard] --> API
  Dashboard --> Prom
```

Azure Terraform provisions the cloud infrastructure. The AKS Terraform root installs workloads in the `data`, `serving`, `staging`, and `observability` namespaces. The model API loads MLflow models and Feast online features. Training uses Feast historical retrieval, a temporal split, and MLflow registry artifacts. Drift monitoring, retraining, release gates, and remediation run as AKS workloads.

The dashboard is an AKS service with authentication. Its demo baseline is an MLflow model artifact cached inside its cloud pod. GitHub runners build images and seed demo data; they do not host the application. The UCI credit dataset is real source data, while generated snapshots and injected drift are simulated.
