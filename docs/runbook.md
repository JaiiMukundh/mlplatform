# AKS operations runbook

Use the GitHub **azure** workflow for planned cloud operations. `make azure ACTION=plan` is read-only. `deploy`, `wake`, `destroy`, and `kill` need their confirmation values and current authorization. The cloud script checks ownership before a full kill. `make azure-kill CONFIRMATION=KILL` deletes application, AKS node, and state resource groups owned by this project. Treat Terraform state and Kubernetes Secrets as sensitive.

## Alerts

### ModelApiDown

Check the `serving` deployment and pod logs in AKS, then check Redis, MLflow, and PostgreSQL services in the `data` namespace. The remediator can restart the deployment. If a release caused the outage, use the release rollback procedure in `scripts/model_release.sh`.

### PodCrashLooping

Inspect the terminated container reason, readiness failures, and memory limits. Verify the configured model version exists in MLflow and the Feast online store responds.

### HighErrorRate

Check prediction response codes and model API logs. Confirm feature hydration in Redis and the champion alias in MLflow. Investigate recent releases before rolling back.

### HighP95Latency

Inspect Prometheus request latency, API pod resources, HPA status, and dependency latency. The remediator can raise the HPA floor.

### ModelDriftDetected

Check the drift monitor's window size, consecutive breaches, cooldown, MLflow reference artifact, and retraining Job. Demo drift injection is simulated.

### RetrainFailed

Inspect the retraining Job and its Feast/MLflow dependencies. A candidate must pass gates before promotion. Keep the current champion serving until the failure is resolved.

## Verification

Use `make lint test check-infra check-actions check-manifests secret-scan` for source and configuration checks. A live check runs only after an authorized AKS deployment: verify readiness and model metadata, authenticated dashboard status, prediction, Feast materialization, MLflow champion, and release/drift Job status. Record real results in the deployment run.
