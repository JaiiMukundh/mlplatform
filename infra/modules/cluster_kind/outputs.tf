output "cluster_name" {
  description = "Name of the kind cluster."
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Path of the kubeconfig file written by the kind provider."
  value       = kind_cluster.this.kubeconfig_path
}

output "endpoint" {
  description = "Kubernetes API endpoint of the kind cluster."
  value       = kind_cluster.this.endpoint
}
