variable "db_password" {
  type      = string
  sensitive = true
}

variable "alert_email" {
  type = string
}

variable "admin_cidr" {
  type = string
}

variable "ses_domain" {
  type = string
}

variable "ses_test_email" {
  type = string
}

variable "enable_guardduty" {
  type        = bool
  default     = true
  description = "Some AWS sandbox/academic accounts block GuardDuty at the account level (API calls fail with SubscriptionRequiredException regardless of IAM permissions). Set to false to skip provisioning it on those accounts."
}

variable "github_actions_role_arn" {
  type        = string
  description = "IAM role ARN assumed by the GitHub Actions CI/CD pipeline (see infra/bootstrap). Granted cluster-admin via aws-auth."
  default     = "arn:aws:iam::378780514485:role/cloudmart-github-actions-role"
}

variable "cluster_admin_user_arns" {
  type        = list(string)
  description = "IAM user ARNs granted kubectl cluster-admin access to cloudmart-eks via aws-auth."
  default = [
    "arn:aws:iam::378780514485:user/cloud",
    "arn:aws:iam::378780514485:user/dev-3",
    "arn:aws:iam::378780514485:user/terraform-user",
  ]
}