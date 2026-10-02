variable "namespace" {
  description = "Namespace for the data-layer releases (postgres, minio, redis)."
  type        = string
  default     = "data"
}

variable "metrics_server_version" {
  description = "Pinned metrics-server chart version."
  type        = string
  default     = "3.14.0"
}

variable "metrics_server_repository" {
  description = "Helm repository serving the metrics-server chart."
  type        = string
  default     = "https://kubernetes-sigs.github.io/metrics-server/"
}

variable "postgres_user" {
  description = "Postgres application username (stored in the managed Secret)."
  type        = string
  default     = "mlp"
}

variable "minio_user" {
  description = "MinIO root username (stored in the managed Secret)."
  type        = string
  default     = "minioadmin"
}

variable "buckets" {
  description = "Object-store buckets created by the MinIO bucket Job."
  type        = list(string)
  default     = ["mlflow-artifacts", "feast-offline", "ml-data"]
}
