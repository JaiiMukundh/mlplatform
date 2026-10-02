variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Pinned Kubernetes version for the control plane."
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "VPC hosting the cluster."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for worker nodes."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all created resources."
  type        = map(string)
  default     = {}
}
