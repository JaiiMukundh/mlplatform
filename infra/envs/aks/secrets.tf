resource "kubernetes_namespace_v1" "platform" {
  for_each = toset(["data", "serving", "staging", "observability"])
  metadata {
    name = each.value
  }
}

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "random_password" "grafana" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "postgres" {
  metadata {
    name      = "postgres-auth"
    namespace = "data"
  }
  data = {
    username          = "mlp"
    postgres-password = random_password.postgres.result
  }
  depends_on = [kubernetes_namespace_v1.platform]
}

resource "kubernetes_secret_v1" "minio" {
  metadata {
    name      = "minio-auth"
    namespace = "data"
  }
  data = {
    root-user     = "minioadmin"
    root-password = random_password.minio.result
  }
  depends_on = [kubernetes_namespace_v1.platform]
}

resource "kubernetes_secret_v1" "grafana" {
  metadata {
    name      = "grafana-admin"
    namespace = "observability"
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana.result
  }
  depends_on = [kubernetes_namespace_v1.platform]
}

resource "kubernetes_secret_v1" "postgres_app" {
  for_each = toset(["serving", "staging", "observability"])
  metadata {
    name      = each.value == "observability" ? "drift-monitor-db" : "postgres-app"
    namespace = each.value
  }
  data = {
    database-url = "postgresql+psycopg://mlp:${random_password.postgres.result}@postgres.data.svc:5432/mlp"
  }
  depends_on = [kubernetes_namespace_v1.platform]
}

resource "kubernetes_secret_v1" "dashboard_data" {
  metadata {
    name      = "dashboard-data"
    namespace = "observability"
  }
  data = {
    access-key = "minioadmin"
    secret-key = random_password.minio.result
  }
  depends_on = [kubernetes_namespace_v1.platform]
}

resource "tls_private_key" "dashboard" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "dashboard" {
  private_key_pem       = tls_private_key.dashboard.private_key_pem
  validity_period_hours = 48
  allowed_uses          = ["server_auth"]
  dns_names             = [var.public_host]
  subject {
    common_name = var.public_host
  }
}

resource "kubernetes_secret_v1" "dashboard_tls" {
  metadata {
    name      = "dashboard-tls"
    namespace = "observability"
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = tls_self_signed_cert.dashboard.cert_pem
    "tls.key" = tls_private_key.dashboard.private_key_pem
  }
  depends_on = [kubernetes_namespace_v1.platform]
}
