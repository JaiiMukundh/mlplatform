# Observability stack (P5): kube-prometheus-stack, Loki, Alloy,
# plus our dashboards/alerts content chart. Versions pinned; see docs/VERSIONS.md.

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }

  data = {
    "admin-user"     = var.grafana_user
    "admin-password" = random_password.grafana.result
  }

  depends_on = [kubernetes_namespace_v1.observability]
}

# All three upstream charts are vendored under infra/charts/ (see
# docs/DECISIONS.md): the asset host times out for helm/tofu downloads.
resource "helm_release" "kube_prometheus_stack" {
  name  = "kube-prometheus-stack"
  chart = "${path.module}/../../../infra/charts/kube-prometheus-stack-91.8.2.tgz"
  namespace = kubernetes_namespace_v1.observability.metadata[0].name

  values = [
    file("${path.module}/../../../deploy/charts/observability/values-prometheus.yaml"),
  ]

  wait    = true
  timeout = 900

  depends_on = [kubernetes_secret_v1.grafana_admin]
}

resource "helm_release" "loki" {
  name  = "loki"
  chart = "${path.module}/../../../infra/charts/loki-7.3.0.tgz"
  # Vendored (see docs/DECISIONS.md): the upstream asset host times out
  # for helm/tofu downloads, while the pinned .tgz is byte-identical.
  namespace = kubernetes_namespace_v1.observability.metadata[0].name

  values = [
    file("${path.module}/../../../deploy/charts/observability/values-loki.yaml"),
  ]

  wait    = true
  timeout = 600

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "alloy" {
  name  = "alloy"
  chart = "${path.module}/../../../infra/charts/alloy-1.13.0.tgz"
  namespace = kubernetes_namespace_v1.observability.metadata[0].name

  values = [
    file("${path.module}/../../../deploy/charts/observability/values-alloy.yaml"),
  ]

  wait    = true
  timeout = 600

  depends_on = [helm_release.loki]
}

resource "helm_release" "observability_content" {
  name      = "observability-content"
  chart     = "${path.module}/../../../deploy/charts/observability"
  namespace = kubernetes_namespace_v1.observability.metadata[0].name

  wait    = true
  timeout = 300

  depends_on = [helm_release.kube_prometheus_stack]
}
