output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "app_instance_profile_name" {
  value = aws_iam_instance_profile.app.name
}

output "cross_account_role_arn" {
  value = try(aws_iam_role.xacct[0].arn, null)
}
