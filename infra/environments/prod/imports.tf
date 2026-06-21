# One-time import: the vpc-cni addon was created directly via `aws eks
# create-addon` (to enable NetworkPolicy enforcement immediately, ahead of a
# full plan/apply cycle) and needs to be attached to Terraform state before
# `module.eks.aws_eks_addon.vpc_cni` can be managed normally. Safe to remove
# once the first `terraform apply` after this lands has run successfully.
import {
  to = module.eks.aws_eks_addon.vpc_cni
  id = "cloudmart-eks:vpc-cni"
}
