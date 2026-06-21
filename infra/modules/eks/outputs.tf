output "cluster_name" { value = aws_eks_cluster.main.name }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.eks.arn }
output "oidc_provider_url" { value = aws_eks_cluster.main.identity[0].oidc[0].issuer }
output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_ca_certificate" { value = aws_eks_cluster.main.certificate_authority[0].data }
output "alb_controller_role_arn" { value = aws_iam_role.alb_controller.arn }
output "keda_operator_role_arn" { value = aws_iam_role.keda_operator.arn }
output "velero_role_arn" { value = aws_iam_role.velero.arn }