variable "namespace" {
  description = "Namespace for the observability releases."
  type        = string
  default     = "observability"
}

variable "grafana_user" {
  description = "Grafana admin username."
  type        = string
  default     = "admin"
}

variable "kube_prometheus_stack_version" {
  description = "Pinned kube-prometheus-stack chart version."
  type        = string
  default     = "91.8.2"
}

variable "loki_version" {
  description = "Pinned Loki chart version."
  type        = string
  default     = "7.3.0"
}

variable "alloy_version" {
  description = "Pinned Alloy chart version."
  type        = string
  default     = "1.13.0"
}
