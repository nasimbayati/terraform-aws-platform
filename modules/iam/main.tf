# Two IAM patterns that come up in almost every AWS platform interview:
#
#   1. An EC2 role + instance profile. An instance gets temporary credentials
#      from the instance metadata service, so no keys ever live on the box.
#   2. A cross-account role. Another AWS account (an auditor, a data platform
#      such as Databricks, a central security team) assumes it with
#      sts:AssumeRole and an External ID, and gets read-only access to one bucket.

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  partition = data.aws_partition.current.partition
  s3_via    = "s3.${data.aws_region.current.region}.amazonaws.com"
}

# --- 1. EC2 application role ------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app-ec2"
  description        = "Runtime role for app instances in the private subnets"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "app_data" {
  statement {
    sid       = "ListOwnPrefix"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["app/*"]
    }
  }

  statement {
    sid       = "ReadWriteOwnPrefix"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.bucket_arn}/app/*"]
  }

  statement {
    sid       = "UseDataKeyThroughS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.s3_via]
    }
  }
}

resource "aws_iam_role_policy" "app_data" {
  name   = "app-data-bucket"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_data.json
}

# Session Manager instead of SSH: no port 22, no key pairs, every session logged.
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app-ec2"
  role = aws_iam_role.app.name
}

# --- 2. Cross-account read-only role ----------------------------------------

data "aws_iam_policy_document" "xacct_assume" {
  count = length(var.trusted_account_ids) > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [for id in var.trusted_account_ids : "arn:${local.partition}:iam::${id}:root"]
    }
    # The External ID stops the "confused deputy" problem: a third party that
    # serves many customers can't be tricked into using your role for someone else.
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id == null ? "" : var.external_id]
    }
  }
}

resource "aws_iam_role" "xacct" {
  count = length(var.trusted_account_ids) > 0 ? 1 : 0

  name                 = "${var.name}-xacct-reader"
  description          = "Read-only access to the data bucket for trusted external accounts"
  assume_role_policy   = data.aws_iam_policy_document.xacct_assume[0].json
  max_session_duration = 3600

  lifecycle {
    precondition {
      condition     = length(var.external_id == null ? "" : var.external_id) >= 16
      error_message = "Set external_id (16+ characters) when trusted_account_ids is not empty."
    }
  }
}

data "aws_iam_policy_document" "xacct_read" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bucket_arn]
  }

  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptThroughS3"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [local.s3_via]
    }
  }
}

resource "aws_iam_role_policy" "xacct_read" {
  count = length(var.trusted_account_ids) > 0 ? 1 : 0

  name   = "read-data-bucket"
  role   = aws_iam_role.xacct[0].id
  policy = data.aws_iam_policy_document.xacct_read.json
}
