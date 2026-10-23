# Offline tests for the dev root module: wiring and input validation.
# `terraform test` plans against a mocked AWS provider, so no AWS account is needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

run "default_plan_has_no_cross_account_role" {
  command = plan

  assert {
    condition     = output.cross_account_role_arn == null
    error_message = "Cross-account role should not exist unless an account is trusted."
  }

  assert {
    condition     = output.data_bucket == "platform-demo-dev-data-111111111111"
    error_message = "Bucket name should include project, environment and account ID."
  }
}

run "cross_account_role_needs_external_id" {
  command = plan

  variables {
    trusted_account_ids = ["222222222222"]
  }

  expect_failures = [var.cross_account_external_id]
}

run "cross_account_role_with_external_id" {
  command = plan

  variables {
    trusted_account_ids       = ["222222222222"]
    cross_account_external_id = "example-external-id-1234"
  }
}
