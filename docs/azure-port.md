# Azure deployment and operations

Azure Terraform provisions the resource group, network, AKS, Azure Container Registry, public IP, and cost budget. GitHub Actions runs cloud deployment using OIDC and remote Terraform state. A separate AKS Terraform root manages cluster workloads and secrets in remote state.

A temporary AKS test deployment was verified on 2026-10-15 in [GitHub Actions run 38715945979](https://github.com/JaiiMukundh/mlplatform/actions/runs/38715945979). Its endpoints are historical and are not presented as live. Feast jobs, MLflow training and champion promotion, model API prediction, and authenticated dashboard status passed in that run. These results used simulated snapshot dates and demo data. The current Terraform-only changes have not been deployed to AKS.

## GitHub workflows

- `ci.yml` validates Python, cloud Terraform, Kubernetes manifests, images, and security on GitHub-hosted runners.
- `cd.yml` exposes the **azure** workflow. `plan` is read-only. `deploy`, `wake`, `destroy`, and `kill` require explicit confirmation; deploy also requires successful CI for its selected commit.
- `expiry.yml` is a backup teardown check for temporary test sessions. Scheduling may run late; verify full deletion explicitly.

## Configuration and safety

Configure the GitHub `azure` environment with Azure OIDC client, tenant, and subscription IDs; the Terraform state account; an exact region-supported AKS version; budget notification address; and tester CIDR. The Azure identity needs permission for the project resource groups, AKS, ACR pull assignment, and state Blob container. Keep credentials out of Git. The deployment script checks confirmation and resource ownership for destructive operations. The prior 2026-10-13 test authorization is complete; a new billable deployment requires current authorization.

Use Make targets from README to validate, plan, deploy, and tear down. A full kill deletes project-owned application, AKS node, and state resource groups, including test data and model history.
