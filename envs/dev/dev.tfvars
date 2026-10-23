# Non-secret settings for the dev environment. Secrets come from pipeline variables.
region           = "us-east-1"
project          = "platform-demo"
environment      = "dev"
vpc_cidr         = "10.0.0.0/16"
enable_flow_logs = false

# To demo cross-account access with one account, trust your own account ID and
# test with `aws sts assume-role --external-id ...` (see docs/WALKTHROUGH.md).
trusted_account_ids = []
