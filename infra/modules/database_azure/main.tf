# Azure parity for Postgres: Azure Database for PostgreSQL Flexible Server
# with burstable B1ms compute, private VNet integration, and no deletion lock
# for clean teardown.

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.identifier}.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                = "${var.identifier}-vnet-link"
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  virtual_network_id  = var.vnet_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = var.identifier
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.engine_version
  delegated_subnet_id    = var.delegated_subnet_id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.username
  administrator_password = random_password.db.result
  zone                   = "1"

  storage_mb   = 32768
  storage_tier = "P4"
  sku_name     = var.sku_name

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "mlp" {
  name      = "mlp"
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

variable "identifier" {
  description = "Flexible server name (also used for the private DNS zone link)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group holding the server."
  type        = string
}

variable "vnet_id" {
  description = "VNet ID for the private DNS zone link."
  type        = string
}

variable "delegated_subnet_id" {
  description = "Subnet ID delegated to PostgreSQL Flexible Servers."
  type        = string
}

variable "username" {
  description = "Administrator login (password is generated)."
  type        = string
  default     = "mlp"
}

variable "engine_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "Compute SKU (burstable B-series keeps demo cost near zero)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "tags" {
  description = "Tags applied to taggable resources."
  type        = map(string)
  default     = {}
}

output "db_fqdn" {
  description = "Fully qualified domain name of the Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "db_username" {
  description = "Administrator login for connection strings (password lives in state — treat as secret)."
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}

output "db_password" {
  description = "Generated administrator password (sensitive; mirrored into the serving namespace at deploy time)."
  value       = random_password.db.result
  sensitive   = true
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}
