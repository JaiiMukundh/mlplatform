# AWS parity for MinIO: versioned, SSE-encrypted buckets with public access
# blocked. Mirrors the three local buckets (mlflow-artifacts, feast-offline,
# ml-data); the env maps artifact/data roles onto the first two.
locals {
  buckets = {
    artifacts = "${var.bucket_prefix}-mlflow-artifacts"
    offline   = "${var.bucket_prefix}-feast-offline"
    mldata    = "${var.bucket_prefix}-ml-data"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.value
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
