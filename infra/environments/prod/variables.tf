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