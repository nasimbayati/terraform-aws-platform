variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  description = "Must match `project` in bootstrap/, because the pipeline role is scoped to this prefix."
  type        = string
  default     = "platform-demo"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "enable_flow_logs" {
  type    = bool
  default = false
}

variable "trusted_account_ids" {
  description = "Accounts allowed to assume the cross-account reader role."
  type        = list(string)
  default     = []
}

variable "cross_account_external_id" {
  description = "External ID for the cross-account role. Pass it from a secret pipeline variable (TF_VAR_cross_account_external_id), never commit it."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = length(var.trusted_account_ids) == 0 || length(var.cross_account_external_id == null ? "" : var.cross_account_external_id) >= 16
    error_message = "Set cross_account_external_id (16+ characters) when trusted_account_ids is not empty."
  }
}
