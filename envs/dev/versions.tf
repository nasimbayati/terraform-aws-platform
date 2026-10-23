terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: bucket, key, region and kms_key_id come from
  # backend.hcl at `terraform init -backend-config=backend.hcl`, so the same
  # code can point at a different state bucket per environment.
  #
  # use_lockfile = true is S3 native state locking (Terraform 1.10+). Terraform
  # writes a .tflock object next to the state with a conditional write, so two
  # runs can't change state at once. This replaces the older DynamoDB lock
  # table, which is now deprecated.
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/nasimbayati/terraform-aws-platform"
    }
  }
}
