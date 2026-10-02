# The kind cluster is managed imperatively through the kind CLI: the
# tehcyx/kind provider (v0.11.0, latest) bundles kind 0.31.0, whose kubeadm
# cannot init the pinned Kubernetes v1.37.0 nodes, while the kind v0.33.0 CLI
# creates the identical config cleanly. Same pattern as the registry module:
# OpenTofu tracks the rendered config hash, the script does the mutation.
resource "terraform_data" "cluster" {
  triggers_replace = {
    cluster_name    = var.cluster_name
    config_sha256   = local_file.kind_config.content_sha256
    create_sha256   = filesha256("${path.module}/files/create.sh")
    kind_config     = local.kind_config_file
    kubeconfig_file = local.kubeconfig_file
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/files/create.sh\""
    environment = {
      CLUSTER_NAME    = var.cluster_name
      KIND_CONFIG     = local.kind_config_file
      KUBECONFIG_FILE = local.kubeconfig_file
      REGISTRY_SCRIPT = "${path.module}/${var.registry_script_path}"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash \"${path.module}/files/delete.sh\""
    environment = {
      CLUSTER_NAME    = self.triggers_replace.cluster_name
      KIND_CONFIG     = self.triggers_replace.kind_config
      KUBECONFIG_FILE = self.triggers_replace.kubeconfig_file
    }
  }

  depends_on = [local_file.kind_config]
}

resource "local_file" "kind_config" {
  content = templatefile("${path.module}/kind-config.yaml.tftpl", {
    node_image              = var.node_image
    registry_host           = var.registry_host
    registry_container_host = var.registry_container_host
    port_mappings           = var.port_mappings
  })
  filename = local.kind_config_file
}

locals {
  kubeconfig_file  = var.kubeconfig_path != "" ? var.kubeconfig_path : "${path.root}/kubeconfig"
  kind_config_file = "${path.root}/.kind-config.${var.cluster_name}.yaml"
}
