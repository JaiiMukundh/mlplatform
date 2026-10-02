output "artifact_bucket_arn" {
  description = "ARN of the MLflow-artifact bucket."
  value       = aws_s3_bucket.this["artifacts"].arn
}

output "artifact_bucket_name" {
  description = "Name of the MLflow-artifact bucket."
  value       = aws_s3_bucket.this["artifacts"].id
}

output "data_bucket_arn" {
  description = "ARN of the Feast-offline bucket."
  value       = aws_s3_bucket.this["offline"].arn
}

output "data_bucket_name" {
  description = "Name of the Feast-offline bucket."
  value       = aws_s3_bucket.this["offline"].id
}

output "mldata_bucket_arn" {
  description = "ARN of the ml-data bucket."
  value       = aws_s3_bucket.this["mldata"].arn
}
