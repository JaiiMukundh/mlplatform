# Pinned kind cluster reproducing infra/kind-config.yaml via the tehcyx/kind provider.
resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    containerd_config_patches = [
      <<-EOT
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."${var.registry_host}"]
          endpoint = ["http://${var.registry_container_host}"]
      EOT
    ]

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value
          host_port      = tonumber(extra_port_mappings.key)
        }
      }
    }

    node {
      role = "worker"
    }

    node {
      role = "worker"
    }
  }
}
