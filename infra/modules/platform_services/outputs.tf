output "namespace" {
  description = "Namespace hosting the data-layer releases."
  value       = kubernetes_namespace_v1.data.metadata[0].name
}

output "s3_endpoint" {
  description = "Cluster-internal MinIO S3 endpoint."
  value       = "http://${helm_release.minio.name}.${var.namespace}.svc:9000"
}

output "buckets" {
  description = "Object-store buckets created by the MinIO bucket Job."
  value       = var.buckets
}

output "db_host" {
  description = "Cluster-internal PostgreSQL hostname."
  value       = "${helm_release.postgres.name}.${var.namespace}.svc"
}

output "redis_host" {
  description = "Cluster-internal Redis hostname."
  value       = "${helm_release.redis.name}.${var.namespace}.svc"
}

output "postgres_secret_name" {
  description = "Name of the Secret holding the Postgres credentials."
  value       = kubernetes_secret_v1.postgres_auth.metadata[0].name
}

output "minio_secret_name" {
  description = "Name of the Secret holding the MinIO credentials."
  value       = kubernetes_secret_v1.minio_auth.metadata[0].name
}
