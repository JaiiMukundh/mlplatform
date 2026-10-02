output "cluster_name" {
  description = "Name of the kind cluster."
  value       = terraform_data.cluster.triggers_replace.cluster_name
}

output "kubeconfig_path" {
  description = "Path of the standalone kubeconfig file written at creation."
  # Guarded by an apply-time-known attribute so that provider configurations
  # built on this output (kubernetes/helm in envs/local) are deferred until
  # the cluster exists. Without this, those providers stat the kubeconfig
  # during plan and fail because the file is not written yet.
  value = terraform_data.cluster.id == null ? null : local.kubeconfig_file
}
