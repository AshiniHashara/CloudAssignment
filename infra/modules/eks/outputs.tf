output "cluster_name" { value = aws_eks_cluster.main.name }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.eks.arn }
output "oidc_provider_url" { value = aws_eks_cluster.main.identity[0].oidc[0].issuer }