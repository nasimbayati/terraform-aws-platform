variable "name" {
  description = "Prefix for resource names and Name tags."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR. Must be a /16 so the subnet math in main.tf works."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && endswith(var.cidr_block, "/16")
    error_message = "cidr_block must be a valid /16, for example 10.0.0.0/16."
  }
}

variable "az_count" {
  description = "How many Availability Zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "enable_nat_gateway" {
  description = "Add one NAT Gateway for outbound internet from private subnets. Costs about $32/month plus data."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Send rejected-traffic VPC Flow Logs to CloudWatch (7-day retention)."
  type        = bool
  default     = false
}
