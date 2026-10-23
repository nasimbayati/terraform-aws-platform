data "aws_caller_identity" "current" {}

locals {
  name        = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${local.name}-data-${local.account_id}"

  # Built as a string so the bucket policy can name the role before it exists.
  app_role_arn = "arn:aws:iam::${local.account_id}:role/${local.name}-app-ec2"
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  cidr_block         = var.vpc_cidr
  az_count           = 2
  enable_nat_gateway = false
  enable_flow_logs   = var.enable_flow_logs
}

module "storage" {
  source = "../../modules/storage"

  bucket_name        = local.bucket_name
  vpc_endpoint_id    = module.network.s3_endpoint_id
  vpc_only_role_arns = [local.app_role_arn]
  force_destroy      = true # demo environment: allow a clean `terraform destroy`
}

module "iam" {
  source = "../../modules/iam"

  name                = local.name
  bucket_arn          = module.storage.bucket_arn
  kms_key_arn         = module.storage.kms_key_arn
  trusted_account_ids = var.trusted_account_ids
  external_id         = var.cross_account_external_id
}
