variable "region" {
  description = "AWS region for the state bucket and pipeline roles."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name used as a prefix for every resource. Lowercase letters, digits and hyphens."
  type        = string
  default     = "platform-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project))
    error_message = "project must be 3-20 characters of lowercase letters, digits or hyphens."
  }
}

variable "ado_organization_id" {
  description = "Azure DevOps organization GUID (not the name). Shown in the OIDC issuer URL; see docs/SETUP.md for how to find it."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f-]{36}$", var.ado_organization_id))
    error_message = "ado_organization_id must be a GUID like 12345678-abcd-..."
  }
}

variable "ado_organization_name" {
  description = "Azure DevOps organization name, as in dev.azure.com/<name>."
  type        = string
}

variable "ado_project_name" {
  description = "Azure DevOps project that runs the pipeline."
  type        = string
}

variable "ado_plan_service_connection" {
  description = "Name of the AWS service connection the plan stage uses."
  type        = string
  default     = "aws-plan"
}

variable "ado_apply_service_connection" {
  description = "Name of the AWS service connection the apply stage uses."
  type        = string
  default     = "aws-apply"
}
