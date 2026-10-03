# AWS parity environment. Never apply without the human step in P9.6.
# Only init -backend=false, validate, and plan are allowed here.
locals {
  name = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "opentofu"
  }
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "../../modules/network_vpc"

  name               = local.name
  availability_zones = 2
  tags               = local.tags
}

module "cluster" {
  source = "../../modules/cluster_eks"

  cluster_name       = local.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  tags               = local.tags
}

module "storage" {
  source = "../../modules/object_storage"

  bucket_prefix = local.name
  tags          = local.tags
}

module "db" {
  source = "../../modules/database"

  identifier         = local.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  tags               = local.tags
}

module "registry" {
  source = "../../modules/image_registry"

  project = var.project
}

module "api_access" {
  source = "../../modules/iam"

  project                   = var.project
  oidc_provider_arn         = module.cluster.oidc_provider_arn
  oidc_provider_url         = module.cluster.oidc_provider_url
  artifact_bucket_arn       = module.storage.artifact_bucket_arn
  data_bucket_arn           = module.storage.data_bucket_arn
  namespace                 = "serving"
  service_account_model_api = "model-api"
  service_account_retrain   = "retrain"
  service_account_mlflow    = "mlflow"
}

# Cost guardrail for the demo window (P9.6 tears everything down).
resource "aws_sns_topic" "budget" {
  name = "${local.name}-budget"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "budget_email" {
  count = var.budget_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.budget.arn
  protocol  = "email"
  endpoint  = var.budget_email
}

resource "aws_budgets_budget" "monthly" {
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.budget.arn]
  }
}
