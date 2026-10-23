output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "data_bucket" {
  value = module.storage.bucket_name
}

output "data_kms_key_arn" {
  value = module.storage.kms_key_arn
}

output "app_instance_profile" {
  value = module.iam.app_instance_profile_name
}

output "cross_account_role_arn" {
  value = module.iam.cross_account_role_arn
}
