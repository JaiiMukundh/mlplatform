# AWS parity for kind-registry: one ECR repository per service image,
# with image scanning on push.
locals {
  images = ["model-api", "drift-monitor", "retrain", "remediator", "mlflow"]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.images)

  name = "${var.project}/${each.value}"

  image_scanning_configuration {
    scan_on_push = true
  }
}
