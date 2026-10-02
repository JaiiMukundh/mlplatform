# AWS parity for "cluster": managed EKS with a 2x t3.medium node group, IRSA
# enabled, and the EBS CSI addon (EBS-backed PVCs in P9).
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public endpoint (laptop kubectl, no VPN); private access stays on.
  endpoint_public_access = true

  enable_irsa = true

  addons = {
    aws-ebs-csi-driver = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 2
      desired_size   = 2
    }
  }

  tags = var.tags
}
