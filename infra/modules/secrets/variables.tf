variable "common_tags" {
  type = map(string)
}

variable "kms_key_arn" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "rds_endpoint" {
  type = string
}