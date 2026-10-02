output "role_arns" {
  description = "IRSA role ARNs by service (model-api, retrain, mlflow)."
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
