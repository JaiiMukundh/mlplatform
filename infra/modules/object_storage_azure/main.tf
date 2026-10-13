# Azure parity for MinIO/S3: Azure Blob Storage account with versioned,
# encrypted containers. Mirrors the three platform containers:
# mlflow-artifacts, feast-offline, and ml-data.

locals {
  # Azure storage account names must be lowercase letters/numbers only, 3-24 chars.
  sanitized_name = substr(replace(lower("${var.bucket_prefix}store"), "/[^a-z0-9]/", ""), 0, 24)

  containers = [
    "mlflow-artifacts",
    "feast-offline",
    "ml-data",
  ]
}

resource "azurerm_storage_account" "this" {
  name                     = local.sanitized_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  tags = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each = toset(local.containers)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

variable "bucket_prefix" {
  description = "Prefix sanitized into the storage account name (lowercase alphanumerics, max 24 chars total)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the storage account."
  type        = string
}

variable "tags" {
  description = "Tags applied to the storage account."
  type        = map(string)
  default     = {}
}

output "storage_account_name" {
  description = "Blob Storage account name."
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the Blob Storage account (RBAC scope for workload identities)."
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "Primary Blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
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
