# Data layer + metrics-server, installed from our own pinned charts.
# Credentials are generated here (random_password) and consumed by the charts
# via existingSecret, so no password is ever committed to git.

resource "kubernetes_namespace_v1" "data" {
  metadata {
    name = var.namespace
  }
}

# Alphanumeric only: these passwords end up inside URLs (DATABASE_URL, S3
# endpoint overrides), where special characters would need escaping.
resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "minio" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "postgres_auth" {
  metadata {
    name      = "postgres-auth"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
  }

  data = {
    "username"          = var.postgres_user
    "postgres-password" = random_password.postgres.result
  }

  depends_on = [kubernetes_namespace_v1.data]
}

resource "kubernetes_secret_v1" "minio_auth" {
  metadata {
    name      = "minio-auth"
    namespace = kubernetes_namespace_v1.data.metadata[0].name
  }

  data = {
    "root-user"     = var.minio_user
    "root-password" = random_password.minio.result
  }

  depends_on = [kubernetes_namespace_v1.data]
}

resource "helm_release" "metrics_server" {
  name  = "metrics-server"
  chart = "${path.module}/../../../infra/charts/metrics-server-3.14.0.tgz"
  # Vendored (see docs/DECISIONS.md): the asset host times out for helm/tofu.
  namespace = "kube-system"

  # Required on kind (same flag as the P2.3 imperative install).
  set = [{
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }]

  wait    = true
  timeout = 300
}

resource "helm_release" "postgres" {
  name      = "postgres"
  chart     = "${path.module}/../../../deploy/charts/postgres"
  namespace = kubernetes_namespace_v1.data.metadata[0].name

  set = [
    {
      name  = "auth.createSecret"
      value = "false"
    },
    {
      name  = "auth.existingSecret"
      value = kubernetes_secret_v1.postgres_auth.metadata[0].name
    },
  ]

  wait    = true
  timeout = 600

  depends_on = [kubernetes_secret_v1.postgres_auth]
}

resource "helm_release" "minio" {
  name      = "minio"
  chart     = "${path.module}/../../../deploy/charts/minio"
  namespace = kubernetes_namespace_v1.data.metadata[0].name

  set = [
    {
      name  = "auth.createSecret"
      value = "false"
    },
    {
      name  = "auth.existingSecret"
      value = kubernetes_secret_v1.minio_auth.metadata[0].name
    },
  ]

  wait    = true
  timeout = 600

  depends_on = [kubernetes_secret_v1.minio_auth]
}

resource "helm_release" "redis" {
  name      = "redis"
  chart     = "${path.module}/../../../deploy/charts/redis"
  namespace = kubernetes_namespace_v1.data.metadata[0].name

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace_v1.data]
}
