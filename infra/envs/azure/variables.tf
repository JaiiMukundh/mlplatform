variable "subscription_id" {
  description = "Azure Subscription ID. No default: every student has their own subscription, so this must come from terraform.tfvars (see terraform.tfvars.example)."
  type        = string
}

variable "project" {
  description = "Project prefix for resource names."
  type        = string
  default     = "mlp"
}

variable "environment" {
  description = "Environment suffix for resource names."
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "indiasouthcentral"
}

variable "vnet_cidr" {
  description = "Address space for the VNet (used by the AKS subnet)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Exact supported AKS patch version, selected from the target region before deployment."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Set an exact AKS patch version supported in your region; no obsolete or floating default is selected."
  }
}

variable "node_count" {
  description = "AKS default node-pool count."
  type        = number
  default     = 2

  # Edu/Students cap: Total Regional vCPUs is typically 4, and every node
  # SKU allowed here is 2 vCPU, so more than 2 nodes cannot be scheduled.
  # Quota increases are NOT available on student subscriptions.
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 2
    error_message = "node_count must be 1-2: student subscriptions cap Total Regional vCPUs (2 vCPU per node)."
  }
}

variable "vm_size" {
  description = "AKS node VM SKU."
  type        = string
  default     = "Standard_B2s"

  # AKS needs >=2 vCPU and realistically >=4 GB RAM per node for kube-system
  # plus platform pods. Standard_B2ats_v2 (2 vCPU / 1 GB) is deliberately
  # excluded: kubelet fails with 0 allocatable memory on 1 GB nodes.
  # B-series v1 (B2s) is retiring in some regions; if the preflight reports
  # NotAvailableForSubscription, switch to Standard_B2as_v2 (2 vCPU / 8 GB).
  validation {
    condition = contains(
      ["Standard_B2s", "Standard_B2as_v2", "Standard_B2als_v2"],
      var.vm_size,
    )
    error_message = "vm_size must be a 2-vCPU burstable SKU with >=4 GB RAM (Standard_B2s, Standard_B2as_v2, Standard_B2als_v2). 1 GB SKUs (B2ats_v2/B2pts_v2) cannot run AKS kubelets."
  }
}

variable "budget_limit_usd" {
  description = "Monthly budget guardrail in USD."
  type        = number
  default     = 50
}

variable "budget_email" {
  description = "Email for budget alerts."
  type        = string
  default     = "your-email@example.com"
}

variable "budget_start_date" {
  description = "Budget window start (first of month, UTC)."
  type        = string
  default     = "2026-10-01T00:00:00Z"
}

variable "expires_at" {
  description = "UTC test-session deadline; GitHub expiry deletes the full environment after this time."
  type        = string
  default     = ""
}
