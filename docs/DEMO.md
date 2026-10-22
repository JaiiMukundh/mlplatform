# AKS demo guide

1. Use the GitHub **azure** workflow to deploy an authorized test session. Wait for its cloud smoke checks and obtain the current dashboard URL from that run. Do not assume historical addresses still work.
2. Sign in to the HTTPS operations dashboard with the credential stored in the AKS Secret. Use its health, model, and observability views.
3. Verify the API readiness, model metadata, and prediction route through the deployed endpoint. The model should be the MLflow `champion` and features should come from Feast online storage.
4. Show the Feast materialization and training Jobs, the MLflow model version, and the candidate release gate in AKS.
5. Demonstrate pod recovery or injected latency through the cloud dashboard. Observe Prometheus alerts and remediator actions.
6. Trigger the synthetic drift demo through the dashboard. Observe consecutive drift detection, the AKS retraining Job, candidate evaluation, and release outcome.
7. End the test session with the authorized full-kill operation and verify project-owned resource groups are gone.

The source UCI credit records are real; the snapshot timeline and drift injection are synthetic. Historical model scores are not evidence of a production credit system.
