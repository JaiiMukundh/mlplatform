output "registry_url" {
  description = "Host-facing URL of the local container registry."
  value       = "localhost:${var.registry_port}"
}

output "registry_name" {
  description = "Name of the local registry container."
  value       = var.registry_name
}
