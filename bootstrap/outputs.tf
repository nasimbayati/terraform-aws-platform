output "state_bucket" {
  description = "Put this in envs/dev/backend.hcl as `bucket`."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "Put this in envs/dev/backend.hcl as `kms_key_id`."
  value       = aws_kms_key.state.arn
}

output "plan_role_arn" {
  description = "Role ARN for the `aws-plan` service connection in Azure DevOps."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role ARN for the `aws-apply` service connection in Azure DevOps."
  value       = aws_iam_role.apply.arn
}
