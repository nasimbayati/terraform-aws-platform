# Bootstrap: everything the pipeline needs before it can run.
#
# Applied ONCE, by a human, from a laptop, with local state. It creates:
#   1. A KMS key and an S3 bucket that hold Terraform remote state for envs/*.
#   2. An IAM OIDC identity provider that trusts Azure DevOps.
#   3. Two IAM roles the pipeline assumes through OIDC: one read-only for
#      `plan`, one with write access for `apply`.
#
# This is the classic chicken-and-egg of Terraform: the state bucket and the
# pipeline's own identity can't be created by the pipeline, so they live here.

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  state_bucket = "${var.project}-tfstate-${local.account_id}"

  # Azure DevOps issues OIDC tokens from https://vstoken.dev.azure.com/<org GUID>.
  ado_issuer_host = "vstoken.dev.azure.com/${var.ado_organization_id}"

  # The token's `sub` claim names the exact service connection that asked for it:
  # sc://<organization>/<project>/<service connection>
  ado_subject_prefix = "sc://${var.ado_organization_name}/${var.ado_project_name}"
}

# ---------------------------------------------------------------------------
# Remote state: KMS key + S3 bucket
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "state_key" {
  #checkov:skip=CKV_AWS_111:Standard KMS key policy; in a key policy "*" means this key only
  #checkov:skip=CKV_AWS_356:Standard KMS key policy; in a key policy "*" means this key only
  #checkov:skip=CKV_AWS_109:Standard KMS key policy; access is delegated to IAM in this account
  # Same as the AWS default key policy, written out so it is reviewed in code:
  # the account owns the key, and IAM policies decide who may use it.
  statement {
    sid       = "EnableIamPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform state for ${var.project}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; versioning plus CloudTrail is enough for a demo
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles cost; versioning covers accidental overwrites
  #checkov:skip=CKV2_AWS_62:No consumer for event notifications on the state bucket
  bucket = local.state_bucket

  # State is the source of truth for what Terraform owns. Losing it means
  # re-importing every resource by hand, so refuse to delete it by accident.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------------------------------------------------------------------------
# Azure DevOps -> AWS federation (OIDC, no long-lived access keys)
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "azure_devops" {
  url            = "https://${local.ado_issuer_host}"
  client_id_list = ["api://AzureADTokenExchange"]
}

# Builds a trust policy that only accepts tokens minted for one named
# Azure DevOps service connection.
data "aws_iam_policy_document" "pipeline_trust" {
  for_each = {
    plan  = var.ado_plan_service_connection
    apply = var.ado_apply_service_connection
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.azure_devops.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.ado_issuer_host}:aud"
      values   = ["api://AzureADTokenExchange"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.ado_issuer_host}:sub"
      values   = ["${local.ado_subject_prefix}/${each.value}"]
    }
  }
}

# Both roles need to read and write state (plan takes a lock, too).
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "ReadWriteStateAndLockFiles"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid = "UseStateKey"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [aws_kms_key.state.arn]
  }
}

# --- plan role: read-only on the account, read/write on state only ---------

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-ado-plan"
  description          = "Assumed by the Azure DevOps plan stage via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.pipeline_trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan_state" {
  name   = "terraform-state"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.state_access.json
}

# --- apply role: can change only the services this project uses ------------

data "aws_iam_policy_document" "apply" {
  #checkov:skip=CKV_AWS_111:Demo scope. Writes are limited to the services this project uses; see docs/DECISIONS.md
  #checkov:skip=CKV_AWS_356:EC2 and S3 resources do not exist before apply, so they cannot be named in advance
  #checkov:skip=CKV_AWS_108:The deploy role has to read and write the data bucket it manages
  #checkov:skip=CKV_AWS_109:IAM writes are limited to the project name prefix, and the pipeline roles are denied
  #checkov:skip=CKV_AWS_107:Accepted for the deploy role; there are no IAM users or access keys in this project
  statement {
    sid = "ManageProjectServices"
    actions = [
      "ec2:*",
      "s3:*",
      "kms:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  # IAM is where privilege escalation happens, so the apply role may only
  # touch roles, policies and instance profiles whose names start with the
  # project prefix. It cannot create users, and the Deny below stops it from
  # editing the pipeline roles themselves.
  statement {
    sid = "ManageProjectIamOnly"
    actions = [
      "iam:*Role*",
      "iam:*Policy*",
      "iam:*InstanceProfile*",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:policy/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Belt and braces: even if the patterns above are widened later, the
  # pipeline must never be able to rewrite its own permissions.
  statement {
    sid     = "ProtectPipelineRoles"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-ado-*",
      "arn:${local.partition}:iam::${local.account_id}:oidc-provider/*",
    ]
  }
}

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-ado-apply"
  description          = "Assumed by the Azure DevOps apply stage via OIDC"
  assume_role_policy   = data.aws_iam_policy_document.pipeline_trust["apply"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "apply_services" {
  name   = "project-services"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}

resource "aws_iam_role_policy" "apply_state" {
  name   = "terraform-state"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.state_access.json
}
