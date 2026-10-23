variable "bucket_name" {
  description = "Globally unique S3 bucket name. Also used for the KMS alias."
  type        = string
}

variable "vpc_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID. When set, roles in vpc_only_role_arns can only reach objects through it."
  type        = string
  default     = null
}

variable "vpc_only_role_arns" {
  description = "Role ARNs that must come through the VPC endpoint. ARNs are matched as strings, so the roles do not need to exist yet."
  type        = list(string)
  default     = []
}

variable "force_destroy" {
  description = "Let `terraform destroy` delete a bucket that still has objects. Handy for a demo, never for real data."
  type        = bool
  default     = false
}
