terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial configuration: bucket, key, region, kms_key_id and dynamodb_table
  # come from -backend-config at `terraform init` (backend.hcl locally, the
  # pipeline variable group in CI), so the same code can point at a different
  # state bucket per environment.
  #
  # Locking uses both mechanisms:
  #   - dynamodb_table: the classic lock table. Terraform puts a LockID item
  #     with a conditional write before touching state.
  #   - use_lockfile:   S3 native locking (Terraform 1.10+), a .tflock object
  #     written next to the state with an S3 conditional write.
  # A run must acquire both. HashiCorp now marks the DynamoDB option as
  # deprecated in favour of use_lockfile, so `init` prints a warning; keeping
  # both is the documented migration path.
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
