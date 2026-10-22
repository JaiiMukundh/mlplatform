# AKS resource snapshots

`infra/envs/aks` owns these resources through the Kubernetes Terraform provider. The JSON maps are grouped by dependency stage:

| File | Contents |
|---|---|
| `crds.json` | Prometheus and Grafana custom resource definitions |
| `data.json.tftpl` | PostgreSQL, MinIO, Redis, MLflow, and initialization Jobs |
| `observability.json.tftpl` | Prometheus, Alertmanager, Grafana, Loki, Alloy, and rules |
| `app.json.tftpl` | Serving, staging, drift monitor, retraining, remediator, and dashboard |

The vendor resources are snapshots of pinned upstream releases: Prometheus stack 91.8.2, Loki 7.3.0, and Alloy 1.13.0. Application resources are project owned. Terraform replaces template variables with the commit-based image tag, model version, Azure public IP settings, and host during deployment. Changes to these maps must pass `make check-manifests` and both Terraform validation checks.
