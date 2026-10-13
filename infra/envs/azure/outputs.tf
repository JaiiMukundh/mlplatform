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

output "storage_account_name" {
  description = "Blob Storage account (S3 equivalent) for artifacts and offline features."
  value       = module.storage.storage_account_name
}

output "blob_endpoint" {
  description = "Primary Blob service endpoint."
  value       = module.storage.primary_blob_endpoint
}

output "db_fqdn" {
  description = "PostgreSQL Flexible Server FQDN (mirrored into the serving namespace as a secret at deploy time)."
  value       = module.db.db_fqdn
}

output "db_username" {
  description = "PostgreSQL administrator login."
  value       = module.db.db_username
}

output "db_password" {
  description = "PostgreSQL administrator password (sensitive; used once to seed the serving-namespace secret)."
  value       = module.db.db_password
  sensitive   = true
}

output "workload_client_ids" {
  description = "Workload Identity client IDs keyed by role (model-api/retrain/mlflow) for service-account annotations."
  value       = module.api_access.client_ids
}
