# aws-auth is auto-created by EKS for the managed node group (CONFIG_MAP auth
# mode), so we manage just its data via kubernetes_config_map_v1_data rather
# than owning the whole ConfigMap. The node role entry is reproduced here
# exactly as EKS would write it, so this doesn't fight EKS's own updates to it.
locals {
  aws_auth_role_map = [
    {
      rolearn  = aws_iam_role.eks_nodes.arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
    {
      rolearn  = var.github_actions_role_arn
      username = "github-actions"
      groups   = ["system:masters"]
    },
  ]

  aws_auth_user_map = [
    for arn in var.cluster_admin_user_arns : {
      userarn  = arn
      username = element(split("/", arn), length(split("/", arn)) - 1)
      groups   = ["system:masters"]
    }
  ]
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.aws_auth_role_map)
    mapUsers = yamlencode(local.aws_auth_user_map)
  }

  force = true

  depends_on = [aws_eks_node_group.main]
}
