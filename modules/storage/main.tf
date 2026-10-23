# An S3 bucket for application data, encrypted with a customer managed KMS key.
#
# Why a customer managed key (CMK) instead of the default S3-managed key?
#   - The key policy decides who can decrypt. Even someone with s3:GetObject
#     cannot read objects unless the key policy (or IAM) also lets them use
#     the key. That is a second, independent lock.
#   - CloudTrail logs every Decrypt call, so you can audit who read what.
#   - You can disable or schedule deletion of the key to make data unreadable.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_root = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
}

# --- KMS key -----------------------------------------------------------------

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_111:Standard KMS key policy; in a key policy "*" means this key only
  #checkov:skip=CKV_AWS_356:Standard KMS key policy; in a key policy "*" means this key only
  #checkov:skip=CKV_AWS_109:Standard KMS key policy; access is delegated to IAM in this account
  # Without this statement the key could become unmanageable. It delegates
  # access control to IAM in this account; it does not grant anyone access
  # by itself.
  statement {
    sid       = "EnableIamPoliciesInThisAccount"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  # Nobody else is named here on purpose. Roles get kms:Decrypt through
  # their own IAM policies (see modules/iam), scoped with kms:ViaService so
  # the key can only be used through S3. Keeping principals out of the key
  # policy also avoids a dependency cycle between the key and the roles.
}

resource "aws_kms_key" "this" {
  description             = "Encrypts objects in ${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.this.key_id
}

# --- S3 bucket ---------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; left out to keep the demo small
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles cost; versioning covers accidental overwrites
  #checkov:skip=CKV2_AWS_62:No consumer for event notifications yet
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs entirely
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this.arn
    }
    # S3 Bucket Keys cut KMS request costs by up to 99% for busy buckets.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "cost-controls"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
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

  # Reject uploads that ask for a different key or for SSE-S3, so every
  # object is guaranteed to be under *this* CMK.
  statement {
    sid       = "DenyWrongEncryptionKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.this.arn]
    }
  }

  # Application roles may only reach the bucket from inside the VPC,
  # through the S3 gateway endpoint. Admins and the pipeline are unaffected.
  dynamic "statement" {
    for_each = var.vpc_endpoint_id != null && length(var.vpc_only_role_arns) > 0 ? [1] : []
    content {
      sid     = "AppRolesOnlyFromVpc"
      effect  = "Deny"
      actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "ArnEquals"
        variable = "aws:PrincipalArn"
        values   = var.vpc_only_role_arns
      }
      condition {
        test     = "StringNotEquals"
        variable = "aws:SourceVpce"
        values   = [var.vpc_endpoint_id]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
