output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EKS nodes, RDS)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (load balancers, NAT)."
  value       = module.vpc.public_subnets
}

output "vpc_cidr" {
  description = "CIDR block of the created VPC."
  value       = module.vpc.vpc_cidr_block
}
