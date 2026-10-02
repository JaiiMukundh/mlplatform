# AWS parity for static MinIO creds: least-privilege IRSA roles. model-api
# reads buckets; retrain and mlflow read and write.
locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")

  roles = {
    model-api = {
      service_account = var.service_account_model_api
      actions         = ["s3:GetObject", "s3:ListBucket"]
    }
    retrain = {
      service_account = var.service_account_retrain
      actions         = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    }
    mlflow = {
      service_account = var.service_account_mlflow
      actions         = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name = "${var.project}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${var.namespace}:${each.value.service_account}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "buckets" {
  for_each = local.roles

  name = "${var.project}-${each.key}-buckets"
  role = aws_iam_role.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = each.value.actions
      Resource = [
        var.artifact_bucket_arn,
        "${var.artifact_bucket_arn}/*",
        var.data_bucket_arn,
        "${var.data_bucket_arn}/*",
      ]
    }]
  })
}
