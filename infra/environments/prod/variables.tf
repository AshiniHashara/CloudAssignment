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