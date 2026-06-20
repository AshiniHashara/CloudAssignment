locals {
  oidc_issuer = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
  namespaces  = ["cloudmart-prod", "cloudmart-staging"]
}

# product-service: DynamoDB read/write on products table only
resource "aws_iam_role" "product_service" {
  name = "cloudmart-product-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = [for ns in local.namespaces : "system:serviceaccount:${ns}:product-service"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "product_service" {
  name = "cloudmart-product-service-policy"
  role = aws_iam_role.product_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan", "dynamodb:Query"]
      Resource = [var.dynamodb_products_arn, "${var.dynamodb_products_arn}/index/*"]
    }]
  })
}

# order-service: SQS send/receive on orders queue only
resource "aws_iam_role" "order_service" {
  name = "cloudmart-order-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = [for ns in local.namespaces : "system:serviceaccount:${ns}:order-service"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "order_service" {
  name = "cloudmart-order-service-policy"
  role = aws_iam_role.order_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = var.sqs_orders_queue_arn
    }]
  })
}

# notification-service: SQS receive/delete + SES send
resource "aws_iam_role" "notification_service" {
  name = "cloudmart-notification-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = [for ns in local.namespaces : "system:serviceaccount:${ns}:notification-service"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "notification_service" {
  name = "cloudmart-notification-service-policy"
  role = aws_iam_role.notification_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_orders_queue_arn
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      }
    ]
  })
}

# user-service: Secrets Manager read-only on RDS credentials secret only
resource "aws_iam_role" "user_service" {
  name = "cloudmart-user-service-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = [for ns in local.namespaces : "system:serviceaccount:${ns}:user-service"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "user_service" {
  name = "cloudmart-user-service-policy"
  role = aws_iam_role.user_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = var.rds_secret_arn
    }]
  })
}

# Velero: backs up Kubernetes resources + EBS volume snapshots to the DR bucket
resource "aws_iam_role" "velero" {
  name = "cloudmart-velero-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:velero:velero-server"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "velero" {
  name = "cloudmart-velero-policy"
  role = aws_iam_role.velero.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeVolumes", "ec2:DescribeSnapshots", "ec2:CreateTags", "ec2:CreateVolume", "ec2:CreateSnapshot", "ec2:DeleteSnapshot"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject", "s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = "${var.velero_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.velero_bucket_arn
      }
    ]
  })
}
