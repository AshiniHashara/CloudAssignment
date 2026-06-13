output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = { for k, v in aws_subnet.public : k => v.id }
}

output "private_app_subnet_ids" {
  value = { for k, v in aws_subnet.private_app : k => v.id }
}

output "private_data_subnet_ids" {
  value = [for s in aws_subnet.private_data : s.id]
}

output "eks_nodes_sg_id" {
  value = aws_security_group.eks_nodes.id
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}