variable "project" {
  description = "Name prefix for IAM roles."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider (from the EKS module)."
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the cluster OIDC provider (https://...)."
  type        = string
}

variable "artifact_bucket_arn" {
  description = "ARN of the MLflow-artifact bucket."
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the Feast-offline bucket."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service accounts."
  type        = string
  default     = "serving"
}

variable "service_account_model_api" {
  description = "ServiceAccount name for model-api (read-only)."
  type        = string
  default     = "model-api"
}

variable "service_account_retrain" {
  description = "ServiceAccount name for retrain (read-write)."
  type        = string
  default     = "retrain"
}

variable "service_account_mlflow" {
  description = "ServiceAccount name for MLflow (read-write)."
  type        = string
  default     = "mlflow"
}
