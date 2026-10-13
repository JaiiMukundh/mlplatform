# Azure parity for IRSA / IAM: Azure User-Assigned Managed Identities with
# Azure Workload Identity (federated credentials) and least-privilege RBAC.

locals {
  identities = {
    model-api = {
      service_account = var.service_account_model_api
      role_definition = "Storage Blob Data Reader"
    }
    retrain = {
      service_account = var.service_account_retrain
      role_definition = "Storage Blob Data Contributor"
    }
    mlflow = {
      service_account = var.service_account_mlflow
      role_definition = "Storage Blob Data Contributor"
    }
  }
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identities

  name                = "${var.project}-${each.key}-id"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  for_each = local.identities

  name                      = "${var.project}-${each.key}-federated"
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.key].id
  subject                   = "system:serviceaccount:${var.namespace}:${each.value.service_account}"
}

resource "azurerm_role_assignment" "storage" {
  for_each = local.identities

  scope                = var.storage_account_id
  role_definition_name = each.value.role_definition
  principal_id         = azurerm_user_assigned_identity.this[each.key].principal_id
}

variable "project" {
  description = "Project prefix for identity and credential names."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the identities."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the bound service accounts."
  type        = string
  default     = "serving"
}

variable "service_account_model_api" {
  description = "Service account bound to the read-only Blob identity."
  type        = string
  default     = "model-api"
}

variable "service_account_retrain" {
  description = "Service account bound to the read-write Blob identity."
  type        = string
  default     = "retrain"
}

variable "service_account_mlflow" {
  description = "Service account bound to the read-write Blob identity."
  type        = string
  default     = "mlflow"
}

variable "oidc_issuer_url" {
  description = "AKS OIDC issuer URL for federated credentials."
  type        = string
}

variable "storage_account_id" {
  description = "Scope for the Blob Data role assignments."
  type        = string
}

variable "tags" {
  description = "Tags applied to the identities."
  type        = map(string)
  default     = {}
}

output "client_ids" {
  description = "Client IDs of the workload identities, keyed by role (model-api/retrain/mlflow). Use in the azure.workload.identity/client-id service-account annotation."
  value       = { for k, id in azurerm_user_assigned_identity.this : k => id.client_id }
}

output "principal_ids" {
  description = "Principal IDs of the workload identities, keyed by role."
  value       = { for k, id in azurerm_user_assigned_identity.this : k => id.principal_id }
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.9.0"
    }
  }
}
