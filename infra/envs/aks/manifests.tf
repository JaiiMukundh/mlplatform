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
  all_manifests = merge(local.manifests.data, local.manifests.observability, local.manifests.app)

  # The Kubernetes API normalizes optional empty/default fields and adds Job
  # controller labels. Tell the provider to accept those exact returned fields
  # while Terraform continues to own every explicitly configured setting.
  api_normalized_fields = {
    for key, manifest in local.all_manifests : key => concat(
      ["metadata.labels", "metadata.annotations"],
      try(manifest.spec.publishNotReadyAddresses, null) == null ? [] : ["spec.publishNotReadyAddresses"],
      try(manifest.spec.template.metadata.labels, null) == null ? [] : ["spec.template.metadata.labels"],
      try(manifest.spec.template.spec.topologySpreadConstraints, null) == null ? [] : ["spec.template.spec.topologySpreadConstraints"],
      try(manifest.spec.template.spec.tolerations, null) == null ? [] : ["spec.template.spec.tolerations"],
      try(manifest.spec.template.spec.initContainers, null) == null ? [] : ["spec.template.spec.initContainers"],
      try(manifest.spec.template.spec.nodeSelector, null) == null ? [] : ["spec.template.spec.nodeSelector"],
      try(manifest.spec.template.spec.hostIPC, null) == null ? [] : ["spec.template.spec.hostIPC"],
      try(manifest.spec.template.spec.hostNetwork, null) == null ? [] : ["spec.template.spec.hostNetwork"],
      flatten([
        for index, container in try(manifest.spec.template.spec.containers, []) : concat(
          try(container.resources.limits, null) == null ? [] : ["spec.template.spec.containers[${index}].resources.limits"],
          try(container.resources.requests, null) == null ? [] : ["spec.template.spec.containers[${index}].resources.requests"],
          try(container.resources.limits.cpu, null) == null ? [] : ["spec.template.spec.containers[${index}].resources.limits[\"cpu\"]"],
          try(container.readinessProbe.initialDelaySeconds, null) == null ? [] : ["spec.template.spec.containers[${index}].readinessProbe.initialDelaySeconds"],
          try(container.livenessProbe.initialDelaySeconds, null) == null ? [] : ["spec.template.spec.containers[${index}].livenessProbe.initialDelaySeconds"]
        )
      ])
    )
  }
}

resource "kubernetes_manifest" "crds" {
  for_each = local.manifests.crds
  manifest = each.value
}

resource "kubernetes_manifest" "data" {
  for_each        = local.manifests.data
  manifest        = each.value
  computed_fields = local.api_normalized_fields[each.key]
  depends_on      = [kubernetes_namespace_v1.platform, kubernetes_secret_v1.postgres, kubernetes_secret_v1.minio]
}

resource "kubernetes_manifest" "observability" {
  for_each        = local.manifests.observability
  manifest        = each.value
  computed_fields = local.api_normalized_fields[each.key]
  depends_on      = [kubernetes_manifest.crds, kubernetes_secret_v1.grafana]
}

resource "kubernetes_manifest" "app" {
  for_each        = local.manifests.app
  manifest        = each.value
  computed_fields = local.api_normalized_fields[each.key]
  depends_on      = [kubernetes_manifest.data, kubernetes_manifest.observability, kubernetes_secret_v1.dashboard_tls, kubernetes_secret_v1.dashboard_data, kubernetes_secret_v1.postgres_app]
}
