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