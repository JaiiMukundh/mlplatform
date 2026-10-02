variable "identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "vpc_id" {
  description = "VPC hosting the database."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "VPC CIDR allowed to reach Postgres (no data source so plan stays offline)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "engine_version" {
  description = "Postgres major version (RDS picks the default minor; re-pin exactly at P9 apply)."
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class (cost-capped for the demo window)."
  type        = string
  default     = "db.t4g.micro"
}

variable "username" {
  description = "Master username."
  type        = string
  default     = "mlp"
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
