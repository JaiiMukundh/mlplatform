# The registry is intentionally imperative: kind's documented local-registry setup
# is a stateful Docker container plus a network attach, which the script performs
# idempotently. OpenTofu only tracks the script hash so edits force a re-run.
resource "terraform_data" "registry" {
  triggers_replace = {
    script_sha256 = filesha256("${path.module}/${var.script_path}")
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/${var.script_path}\""
    environment = {
      REGISTRY_NAME  = var.registry_name
      REGISTRY_PORT  = tostring(var.registry_port)
      REGISTRY_IMAGE = var.registry_image
    }
  }
}
