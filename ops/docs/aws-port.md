# AWS Deployment Runbook & Port Guide (P9.5 / P9.6)

This document provides the exact, production-grade checklist for deploying the ML Platform to AWS (parity target) and tearing it down cleanly.

> [!WARNING]
> **Cost & Safety Guardrail:**
> Running infrastructure on AWS incurs billable charges. The automated AI agent is strictly forbidden from running `tofu apply` against AWS (AGENTS.md Rule 12).
> Applying this environment is strictly a **[HUMAN]** operation (`P9.6`). Keep the AWS environment running ONLY during active testing and the live demo window.

---

## 1. Cost & Architecture Overview

### Resource Cost Matrix (Estimated Hourly Rates in `eu-west-1` / `us-east-1`)
| Component | AWS Resource | Local Parity Alternative | Estimated Hourly Rate | Demo Window (3 hrs) |
|---|---|---|---|---|
| **EKS Control Plane** | Amazon EKS Cluster | Kind multi-node cluster | \$0.10 / hr | \$0.30 |
| **Worker Nodes** | 2x `t3.medium` EC2 | Docker containers (kind-worker) | \$0.0416 * 2 = \$0.0832 / hr | \$0.25 |
| **NAT Gateway** | 1x VPC NAT Gateway + EIP | Docker bridge network | \$0.045 / hr + data | \$0.14 |
| **Database** | RDS PostgreSQL `db.t3.micro` | Bitnami PostgreSQL pod | \$0.018 / hr | \$0.06 |
| **Storage (S3)** | S3 Standard (artifacts + offline) | MinIO S3 pod | < \$0.01 | < \$0.01 |
| **Container Registry**| Amazon ECR | Local Docker registry (localhost:5001) | Free tier / pennies | < \$0.01 |
| **Networking (LoadBalancer)** | AWS NLB (optional; NodePort supported) | Kind port mapping (30080) | \$0.0225 / hr (if provisioned) | \$0.07 |
| **Total Estimated Cost** | | | **~ \$0.27 / hr** | **~ \$0.85** |

*(Local kind execution cost is always \$0.00).*

---

## 2. Pre-Requisites & Human Guardrails (Step 1: [HUMAN])

Before running any OpenTofu commands:
1. **AWS Account & IAM Credentials:**
   - Configure AWS CLI credentials with administrator permissions or SSO:
     ```bash
     aws configure
     # Or: aws sso login --profile mlp-admin
     export AWS_DEFAULT_REGION=eu-west-1
     ```
2. **Set Account Budget Alarm:**
   - Set `var.budget_limit_usd = "50"` and specify your notification email in `infra/envs/aws/terraform.tfvars`:
     ```hcl
     region           = "eu-west-1"
     project          = "mlp"
     environment      = "dev"
     budget_limit_usd = "50"
     budget_email     = "your-email@example.com"
     ```
3. **Verify OpenTofu Validation:**
   ```bash
   make aws-init
   make aws-validate
   ```

---

## 3. Provisioning Cloud Infrastructure (Step 2: [HUMAN])

1. **Review Execution Plan:**
   ```bash
   make aws-plan
   ```
2. **Apply Infrastructure:**
   ```bash
   # Run explicitly as human operator
   tofu -chdir=infra/envs/aws apply -auto-approve
   ```
3. **Capture Outputs:**
   ```bash
   export CLUSTER_NAME=$(tofu -chdir=infra/envs/aws output -raw cluster_name)
   export AWS_REGION="eu-west-1"
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export ARTIFACT_BUCKET=$(tofu -chdir=infra/envs/aws output -raw artifact_bucket)
   export DATA_BUCKET=$(tofu -chdir=infra/envs/aws output -raw data_bucket)
   export RDS_ENDPOINT=$(tofu -chdir=infra/envs/aws output -raw db_endpoint)
   ```
4. **Configure Local Kubeconfig:**
   ```bash
   aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
   kubectl get nodes
   ```

---

## 4. Key Differences: Local (Kind) vs. AWS Production

| Feature | Local Kind Environment | AWS Parity Environment |
|---|---|---|
| **Storage Class** | `standard` (hostpath) | `gp3` (AWS EBS CSI Driver) |
| **Object Storage** | MinIO pod (`http://minio.data.svc:9000`) | Native AWS S3 (`s3://...`) |
| **Object Credentials** | Static credentials secret (`minio-root`) | **IRSA** (IAM Roles for Service Accounts) |
| **Endpoint Overrides** | `AWS_ENDPOINT_URL_S3` / `MLFLOW_S3_ENDPOINT_URL` | Removed: standard AWS public DNS resolution |
| **Metadata Database** | Postgres pod in `data` namespace | Managed Amazon RDS PostgreSQL instance |
| **Container Registry**| `localhost:5001/*` | Amazon ECR (`<ACCOUNT>.dkr.ecr.<REGION>.amazonaws.com/*`) |
| **Ingress / Service** | `NodePort: 30080` via Kind extraPortMappings | `LoadBalancer` (NLB) or `NodePort` + port-forward |
| **Feature Store** | Feast offline Parquet on MinIO | Feast offline Parquet on S3 |
| **Online Store** | Redis pod in `data` namespace | Redis pod (or AWS ElastiCache Redis) |
| **Metrics Server** | Custom `--kubelet-insecure-tls` flag | Standard managed EKS metrics-server addon |

---

## 5. Workload Deployment with Helm Overlays (Step 3: [HUMAN])

### 5.1 Push Images to Amazon ECR
```bash
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Tag and push runtime images
for img in model-api retrain drift-monitor remediator mlflow; do
  docker tag localhost:5001/$img:dev $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mlp-$img:v1.0.0
  docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mlp-$img:v1.0.0
done
```

### 5.2 Create Namespaces and Database Secret
```bash
kubectl create namespace data || true
kubectl create namespace serving || true
kubectl create namespace observability || true

# Mirror RDS database credentials into serving namespace
kubectl create secret generic rds-app \
  --namespace serving \
  --from-literal=database-url="postgresql://mlp:$(aws secretsmanager get-secret-value --secret-id mlp-dev-db --query SecretString --output text)@$RDS_ENDPOINT/mlp"
```

### 5.3 Deploy Model Serving with Overlay
Deploy using the dedicated overlay [deploy/charts/model-api/values-aws.yaml](file:///home/jaiimukundha/Desktop/mlplatform/deploy/charts/model-api/values-aws.yaml):
```bash
helm upgrade --install model-api deploy/charts/model-api \
  -f deploy/charts/model-api/values.yaml \
  -f deploy/charts/model-api/values-aws.yaml \
  --set image.repository="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mlp-model-api" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::$AWS_ACCOUNT_ID:role/mlp-model-api" \
  --namespace serving
```

---

## 6. GitHub Actions CI/CD with AWS OIDC (Step 4)

Instead of long-lived AWS IAM access keys stored as repository secrets, use GitHub Actions OIDC federation:

1. **IAM Role for GitHub Actions:**
   An IAM role with trust policy for `repo:your-org/mlplatform:*`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": {
             "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
           },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": "repo:your-org/mlplatform:*"
           }
         }
       }
     ]
   }
   ```
2. **GitHub Actions Workflow Step:**
   ```yaml
   - name: Configure AWS Credentials via OIDC
     uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-mlp-deploy
       aws-region: eu-west-1

   - name: Login to Amazon ECR
     id: login-ecr
     uses: aws-actions/amazon-ecr-login@v2

   - name: Update Kubeconfig
     run: aws eks update-kubeconfig --region eu-west-1 --name mlp-dev

   - name: Deploy to EKS
     run: make deploy
   ```

---

## 7. Verification and Video Evidence (Step 5)

Run the full end-to-end suite against AWS:
```bash
make e2e
```
Record demo clips (Clip 1: Pod chaos / HPA; Clip 2: Drift detection -> Retraining -> Automated candidate promotion) against the live cloud cluster.

---

## 8. Clean Teardown (Step 6: [HUMAN])

To guarantee zero lingering costs after testing:
1. **Delete Kubernetes Workloads & LoadBalancers:**
   ```bash
   helm uninstall model-api -n serving || true
   kubectl delete service -n serving --all
   ```
2. **Destroy Infrastructure:**
   ```bash
   tofu -chdir=infra/envs/aws destroy -auto-approve
   ```
3. **Audit AWS Console:**
   Verify the following resources are deleted in the AWS Console:
   - [ ] No active EKS clusters
   - [ ] No EC2 instances or lingering NAT Gateways
   - [ ] No Elastic IPs (EIPs) allocated
   - [ ] No orphaned EBS volumes
   - [ ] No active RDS database instances
   - [ ] Check AWS Cost Explorer / Billing Dashboard to confirm \$0.00 active burn rate
