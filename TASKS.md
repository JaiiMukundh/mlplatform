# Tasks

Checkboxes are changed only after the corresponding acceptance check has been observed.

## P0 — Foundations

- [x] P0.1 Create repository layout and foundational files.
- [x] P0.2 Create the Makefile interface.
- [x] P0.3 Implement prerequisite verification.
- [x] P0.4 Build the shared `mlp_common` package.
- [x] P0.5 Configure linting, tests, formatting, and pre-commit.
- [x] P0.6 Establish the Git workflow and PR template.

## P1 — Data, Model, Serving Stub, Containers

- [x] P1.1 Generate deterministic synthetic data.
- [x] P1.2 Train and evaluate the file-backed model.
- [x] P1.3 Implement model-api and provider protocols.
- [x] P1.4 Implement asynchronous prediction logging.
- [x] P1.5 Add model-api tests.
- [x] P1.6 Add the model-api container image.
- [x] P1.7 Wire seed, train, build, and hadolint checks.

## P2 — Kubernetes, HPA, Fault Tolerance

- [x] P2.1 Create the local registry script.
- [x] P2.2 Add the three-node kind configuration.
- [x] P2.3 Install and verify metrics-server.
- [x] P2.4 Create the model-api Helm chart.
- [x] P2.5 Implement atomic deployment and smoke scripts.
- [x] P2.6 Add pod and load chaos scripts.
- [x] P2.7 Add the traffic generator.
- [x] P2.8 Prove zero-error rolling updates.

## P3 — Infrastructure as Code

- [x] P3.1 Implement the kind OpenTofu module.
- [x] P3.2 Implement the registry OpenTofu module.
- [x] P3.3 Create data-service Helm charts.
- [ ] P3.4 Implement the platform-services module.
- [ ] P3.5 Compose the local environment.
- [ ] P3.6 Create AWS-parity modules and environment.
- [ ] P3.7 Add OpenTofu formatting and validation checks.
- [ ] P3.8 Add report-only infrastructure scanning. (stretch)

## P4 — CI/CD

- [ ] P4.1 Install and configure the self-hosted runner. (human)
- [ ] P4.2 Implement continuous integration.
- [ ] P4.3 Implement local continuous deployment.
- [ ] P4.4 Remove model artifacts from the application image.
- [ ] P4.5 Demonstrate branch-to-deployment flow.
- [ ] P4.6 Prove the deployment failure path.
- [ ] P4.7 Add local `act` configuration. (stretch)

## P5 — Observability and Automated Response

- [ ] P5.1 Install the Prometheus stack.
- [ ] P5.2 Install Loki and Grafana Alloy.
- [ ] P5.3 Enable model-api service discovery.
- [ ] P5.4 Provision three dashboards.
- [ ] P5.5 Define alert rules.
- [ ] P5.6 Implement the remediator.
- [ ] P5.7 Prove the alert-response drill.
- [ ] P5.8 Add a Loki-based alert. (stretch)

## P6 — Feature Store and Model Registry

- [ ] P6.1 Deploy MLflow.
- [ ] P6.2 Create the Feast repository.
- [ ] P6.3 Seed and verify Feast data.
- [ ] P6.4 Train via Feast and MLflow.
- [ ] P6.4b Prove training-serving feature parity.
- [ ] P6.5 Implement Feast and MLflow providers.
- [ ] P6.6 Enrich model metadata.
- [ ] P6.7 Prove the full serving flow.
- [ ] P6.8 Document lineage.

## P7 — Model-Aware CI/CD

- [ ] P7.1 Implement candidate gates.
- [ ] P7.2 Implement staging load checks.
- [ ] P7.3 Implement model release automation.
- [ ] P7.4 Run the release drills.
- [ ] P7.5 Add a canary path. (stretch)

## P8 — Drift Detection and Automated Retraining

- [ ] P8.1 Implement and test drift math.
- [ ] P8.2 Implement the drift monitor.
- [ ] P8.3 Implement Kubernetes retrain triggering.
- [ ] P8.4 Implement retraining and dispatch.
- [ ] P8.5 Export retraining metrics.
- [ ] P8.6 Complete the ML health dashboard.
- [ ] P8.7 Implement repeatable drift demos.
- [ ] P8.8 Test retraining safeguards.
- [ ] P8.9 Add performance monitoring. (stretch)
- [ ] P8.10 Add score-distribution drift. (stretch)

## P9 — Integration, Hardening, AWS Port

- [ ] P9.1 Build end-to-end tests.
- [ ] P9.2 Prove a clean-room rebuild.
- [ ] P9.3 Complete hardening.
- [ ] P9.4 Document and test failure modes.
- [ ] P9.5 Prepare the AWS port.
- [ ] P9.6 Execute the AWS port. (human)

## P10 — Documentation and Viva Pack

- [ ] P10.1 Document architecture.
- [ ] P10.2 Complete the runbook.
- [ ] P10.3 Write the technical design document.
- [ ] P10.4 Add the contributions template.
- [ ] P10.5 Write the demo runbook.
- [ ] P10.6 Complete the README.
- [ ] P10.7 Add and update the human-provided viva guide.
