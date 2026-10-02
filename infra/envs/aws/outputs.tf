output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.cluster.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider."
  value       = module.cluster.oidc_provider_arn
}

output "artifact_bucket" {
  description = "Name of the MLflow-artifact bucket."
  value       = module.storage.artifact_bucket_name
}

output "data_bucket" {
  description = "Name of the Feast-offline bucket."
  value       = module.storage.data_bucket_name
}

output "db_endpoint" {
  description = "Connection endpoint of the RDS instance."
  value       = module.db.endpoint
}

output "ecr_repositories" {
  description = "ECR repository URLs by image name."
  value       = module.registry.repository_urls
}

output "role_arns" {
  description = "IRSA role ARNs by service."
  value       = module.api_access.role_arns
}
