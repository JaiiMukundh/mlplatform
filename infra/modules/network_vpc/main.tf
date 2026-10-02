# AWS parity for "network": VPC with public + private subnets across 2 AZs and
# a single NAT gateway (cost-capped for the demo window, per SPEC P3.6).
# AZ names are derived from the region string so that `plan` needs no AWS API
# access (no data sources here).

locals {
  az_letters = ["a", "b", "c", "d"]
  azs        = [for l in slice(local.az_letters, 0, var.availability_zones) : "${var.region}${l}"]

  # /20 blocks: first N public, next N private.
  public_subnets  = [for i in range(var.availability_zones) : cidrsubnet(var.cidr, 4, i)]
  private_subnets = [for i in range(var.availability_zones) : cidrsubnet(var.cidr, 4, i + var.availability_zones)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = var.tags
}
