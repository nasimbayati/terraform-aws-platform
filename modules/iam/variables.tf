variable "name" {
  description = "Prefix for role and instance profile names."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the data bucket the roles get access to."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the bucket."
  type        = string
}

variable "trusted_account_ids" {
  description = "AWS account IDs allowed to assume the cross-account reader role. Empty list = role not created."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Each trusted account ID must be 12 digits."
  }
}

variable "external_id" {
  description = "Shared secret the other account must pass as ExternalId when assuming the role."
  type        = string
  default     = null
  sensitive   = true
}
