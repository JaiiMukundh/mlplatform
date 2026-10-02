output "repository_urls" {
  description = "ECR repository URLs by image name."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
