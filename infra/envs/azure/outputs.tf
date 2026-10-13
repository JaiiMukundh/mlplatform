output "resource_group_name" {
  description = "Resource Group holding the platform."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name (use with az aks get-credentials)."
  value       = module.cluster.cluster_name
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL backing Workload Identity."
  value       = module.cluster.oidc_issuer_url
}

output "acr_login_server" {
  description = "ACR login server (image repository prefix)."
  value       = module.registry.login_server
}
