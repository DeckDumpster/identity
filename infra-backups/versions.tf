terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1"
    }
  }

  # Shared state bucket, S3-native locking, deploy role. The bucket and role are per-account,
  # so they come from -backend-config (see README).
  backend "s3" {
    key          = "identity/infra-backups/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = var.deploy_role_arn
  }
}
