terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "cloudmart-tfstate-g13"
    key            = "cloudmart/bootstrap/terraform.tfstate"
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
    Project   = "cloudmart"
    Team      = "g13"
    ManagedBy = "terraform-bootstrap"
  }
  repo = "AshiniHashara/CloudAssignment"
}

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = local.common_tags
}

# Trusted by: PRs against this repo (plan-only), pushes to main (prod apply/build),
# and pushes to develop (staging build/push). The workflow itself gates the
# terraform apply step to main via a "production" GitHub Environment review.
resource "aws_iam_role" "github_actions" {
  name = "cloudmart-github-actions-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${local.repo}:ref:refs/heads/main",
            "repo:${local.repo}:ref:refs/heads/develop",
            "repo:${local.repo}:pull_request",
            "repo:${local.repo}:environment:production"
          ]
        }
      }
    }]
  })
  tags = local.common_tags
}

# Service-level access to everything Terraform provisions for CloudMart.
# IAM/OIDC-provider management is scoped to cloudmart-* names so this role
# cannot create or modify unrelated IAM principals in the account.
resource "aws_iam_role_policy" "github_actions_infra" {
  name = "cloudmart-terraform-apply-policy"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ServiceWideAccess"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "eks:*",
          "rds:*",
          "dynamodb:*",
          "sqs:*",
          "ecr:*",
          "kms:*",
          "secretsmanager:*",
          "ses:*",
          "cloudwatch:*",
          "logs:*",
          "sns:*",
          "budgets:*",
          "guardduty:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "application-autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "StateBackendAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::cloudmart-tfstate-g13", "arn:aws:s3:::cloudmart-tfstate-g13/*"]
      },
      {
        Sid      = "VeleroBucketAccess"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = ["arn:aws:s3:::cloudmart-velero-backups-*", "arn:aws:s3:::cloudmart-velero-backups-*/*"]
      },
      {
        Sid    = "ScopedIamManagement"
        Effect = "Allow"
        Action = ["iam:*"]
        Resource = [
          "arn:aws:iam::*:role/cloudmart-*",
          "arn:aws:iam::*:policy/cloudmart-*",
          "arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com",
          "arn:aws:iam::*:oidc-provider/oidc.eks.*"
        ]
      },
      {
        Sid      = "IamReadOnly"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
