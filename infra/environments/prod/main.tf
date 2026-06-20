terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "cloudmart-tfstate-g13"
    key            = "cloudmart/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudmart-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  common_tags = {
    Project     = "cloudmart"
    Environment = "prod"
    Team        = "g13"
    ManagedBy   = "terraform"
  }
}

module "kms" {
  source      = "../../modules/kms"
  common_tags = local.common_tags
}

module "vpc" {
  source      = "../../modules/vpc"
  common_tags = local.common_tags
  admin_cidr  = var.admin_cidr
}

module "ecr" {
  source      = "../../modules/ecr"
  common_tags = local.common_tags
  kms_key_arn = module.kms.key_arn
}

module "rds" {
  source          = "../../modules/rds"
  common_tags     = local.common_tags
  kms_key_arn     = module.kms.key_arn
  db_password     = var.db_password
  data_subnet_ids = module.vpc.private_data_subnet_ids
  rds_sg_id       = module.vpc.rds_sg_id
  environment     = "prod"
}

module "secrets" {
  source       = "../../modules/secrets"
  common_tags  = local.common_tags
  kms_key_arn  = module.kms.key_arn
  db_password  = var.db_password
  rds_endpoint = module.rds.endpoint
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  common_tags = local.common_tags
  kms_key_arn = module.kms.key_arn
}

module "sqs" {
  source      = "../../modules/sqs"
  common_tags = local.common_tags
  kms_key_arn = module.kms.key_arn
}

module "ses" {
  source         = "../../modules/ses"
  ses_domain     = var.ses_domain
  ses_test_email = var.ses_test_email
}

module "backup" {
  source      = "../../modules/backup"
  common_tags = local.common_tags
  kms_key_arn = module.kms.key_arn
}

module "eks" {
  source                 = "../../modules/eks"
  common_tags            = local.common_tags
  kms_key_arn            = module.kms.key_arn
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  eks_nodes_sg_id        = module.vpc.eks_nodes_sg_id
  dynamodb_products_arn  = module.dynamodb.table_arn
  sqs_orders_queue_arn   = module.sqs.queue_arn
  rds_secret_arn         = module.secrets.rds_secret_arn
  velero_bucket_arn      = module.backup.bucket_arn
}

module "monitoring" {
  source      = "../../modules/monitoring"
  common_tags = local.common_tags
  alert_email = var.alert_email
}

module "guardduty" {
  count       = var.enable_guardduty ? 1 : 0
  source      = "../../modules/guardduty"
  common_tags = local.common_tags
  alert_email = var.alert_email
}

output "vpc_id" { value = module.vpc.vpc_id }
output "eks_cluster_name" { value = module.eks.cluster_name }
output "ecr_base_url" { value = module.ecr.base_url }
output "sqs_queue_url" { value = module.sqs.queue_url }
output "rds_endpoint" { value = module.rds.endpoint }
output "velero_bucket" { value = module.backup.bucket_name }
output "guardduty_detector_id" { value = var.enable_guardduty ? module.guardduty[0].detector_id : null }