locals {
  manifest_vars = {
    ACR                  = var.acr
    TAG                  = var.image_tag
    IMAGE_TAG            = var.image_tag
    VERSION              = var.model_version
    PUBLIC_IP_NAME       = var.public_ip_name
    PUBLIC_HOST          = var.public_host
    RESOURCE_GROUP       = var.resource_group
    ALLOWED_CIDR         = var.allowed_cidr
    RUNNER_CIDR          = var.runner_cidr
    CLUSTER_NAME         = var.cluster_name
    DASHBOARD_IMAGE      = "${var.acr}/mlp-dashboard:${var.image_tag}"
    MODEL_API_REPOSITORY = "${var.acr}/mlp-model-api"
    TRAINING_IMAGE       = "${var.acr}/mlp-training:${var.image_tag}"
  }
  manifests = {
    crds          = jsondecode(file("${path.module}/../../manifests/crds.json"))
    data          = jsondecode(templatefile("${path.module}/../../manifests/data.json.tftpl", local.manifest_vars))
    observability = jsondecode(templatefile("${path.module}/../../manifests/observability.json.tftpl", local.manifest_vars))
    app           = jsondecode(templatefile("${path.module}/../../manifests/app.json.tftpl", local.manifest_vars))
  }
}

resource "kubernetes_manifest" "crds" {
  for_each = local.manifests.crds
  manifest = each.value
}

resource "kubernetes_manifest" "data" {
  for_each   = { for key, manifest in local.manifests.data : key => manifest if var.stage != "bootstrap" }
  manifest   = each.value
  depends_on = [kubernetes_namespace_v1.platform, kubernetes_secret_v1.postgres, kubernetes_secret_v1.minio]
}

resource "kubernetes_manifest" "observability" {
  for_each   = { for key, manifest in local.manifests.observability : key => manifest if var.stage != "bootstrap" }
  manifest   = each.value
  depends_on = [kubernetes_manifest.crds, kubernetes_secret_v1.grafana]
}

resource "kubernetes_manifest" "app" {
  for_each   = { for key, manifest in local.manifests.app : key => manifest if var.stage == "app" }
  manifest   = each.value
  depends_on = [kubernetes_manifest.data, kubernetes_manifest.observability, kubernetes_secret_v1.dashboard_tls, kubernetes_secret_v1.dashboard_data, kubernetes_secret_v1.postgres_app]
}
