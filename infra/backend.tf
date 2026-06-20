terraform {
  backend "s3" {
    bucket         = "cloudmart-tfstate-g13"
    key            = "cloudmart/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloudmart-tfstate-lock"
    encrypt        = true
  }
}
