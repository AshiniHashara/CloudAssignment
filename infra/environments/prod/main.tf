terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.31" }
    helm       = { source = "hashicorp/helm", version = "~> 2.14" }
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

# Configured against the EKS cluster created by module.eks below — auth uses a
# short-lived token from the AWS provider's own credentials, never a static kubeconfig.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
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

  github_actions_role_arn = var.github_actions_role_arn
  cluster_admin_user_arns = var.cluster_admin_user_arns
}

module "waf" {
  source      = "../../modules/waf"
  common_tags = local.common_tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = "us-east-1"
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.alb_controller_role_arn
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true

  depends_on = [module.eks]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true

  set {
    name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.keda_operator_role_arn
  }

  depends_on = [module.eks]
}

# Backs up Kubernetes resources + EBS volume snapshots to the bucket and IRSA
# role provisioned by module.backup / module.eks.irsa — neither was wired to
# an actual running backup agent until this release.
resource "helm_release" "velero" {
  name             = "velero"
  repository       = "https://vmware-tanzu.github.io/helm-charts"
  chart            = "velero"
  namespace        = "velero"
  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      server = {
        create = true
        name   = "velero-server"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.eks.velero_role_arn
        }
      }
    }
    # IRSA provides credentials — no static AWS keys needed.
    credentials = {
      useSecret = false
    }
    configuration = {
      backupStorageLocation = [{
        name     = "default"
        provider = "aws"
        bucket   = module.backup.bucket_name
        config   = { region = "us-east-1" }
      }]
      volumeSnapshotLocation = [{
        name     = "default"
        provider = "aws"
        config   = { region = "us-east-1" }
      }]
    }
    initContainers = [{
      name  = "velero-plugin-for-aws"
      image = "velero/velero-plugin-for-aws:v1.13.1"
      volumeMounts = [{
        mountPath = "/target"
        name      = "plugins"
      }]
    }]
    # Daily backup of every namespace, 7-day retention — matches the RDS
    # backup retention target (ADR-002) at the Kubernetes-resource layer.
    schedules = {
      daily-backup = {
        schedule = "0 2 * * *"
        template = {
          ttl = "168h0m0s"
        }
      }
    }
  })]

  depends_on = [module.eks, module.backup]
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
output "waf_acl_arn" { value = module.waf.web_acl_arn }
