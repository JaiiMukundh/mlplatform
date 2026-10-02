output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider (for IRSA roles)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "Issuer URL of the cluster OIDC provider."
  value       = "https://${module.eks.oidc_provider}"
}
