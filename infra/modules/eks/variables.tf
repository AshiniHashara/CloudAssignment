variable "common_tags" {
  type = map(string)
}

variable "kms_key_arn" {
  type = string
}

variable "private_app_subnet_ids" {
  type = map(string)
}

variable "public_subnet_ids" {
  type = map(string)
}

variable "eks_nodes_sg_id" {
  type = string
}

variable "dynamodb_products_arn" {
  type = string
}

variable "sqs_orders_queue_arn" {
  type = string
}

variable "rds_secret_arn" {
  type = string
}

variable "velero_bucket_arn" {
  type = string
}

variable "github_actions_role_arn" {
  type        = string
  description = "IAM role ARN assumed by the GitHub Actions CI/CD pipeline. Mapped to system:masters in aws-auth so the pipeline (the cluster's creator) keeps cluster-admin access declaratively instead of relying on EKS's implicit creator grant."
}

variable "cluster_admin_user_arns" {
  type        = list(string)
  description = "IAM user ARNs granted kubectl cluster-admin access via aws-auth (e.g. team members' local AWS CLI users)."
  default     = []
}