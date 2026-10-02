variable "region" {
  description = "AWS region for the parity stack."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Name prefix for AWS resources."
  type        = string
  default     = "mlp"
}

variable "environment" {
  description = "Environment tag for AWS resources."
  type        = string
  default     = "dev"
}

variable "budget_limit_usd" {
  description = "Monthly budget limit (USD) for the cost alarm."
  type        = string
  default     = "50"
}

variable "budget_email" {
  description = "Email receiving budget alerts (empty disables the subscription)."
  type        = string
  default     = ""
}
