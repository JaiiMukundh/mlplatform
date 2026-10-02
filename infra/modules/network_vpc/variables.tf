variable "name" {
  description = "Name prefix for VPC resources."
  type        = string
}

variable "availability_zones" {
  description = "Number of availability zones to span (public + private subnets each)."
  type        = number
  default     = 2
}

variable "cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "region" {
  description = "AWS region (AZ names are derived as <region><letter> so no API lookup is needed)."
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
