variable "environment" {
  description = "The environment the cluster belongs to; the cluster is named after it, one per environment and region."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.environment))
    error_message = "environment is lowercase letters, digits and hyphens."
  }
}

variable "kms_key_arn" {
  description = "The environment's data key: it encrypts ECS Exec sessions between a person and a container."
  type        = string
}

variable "log_kms_key_arn" {
  description = "A key for the ECS Exec log group, whose policy lets CloudWatch Logs use it; null: CloudWatch's own encryption, as every other log group here."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "How long ECS Exec session logs are kept."
  type        = number
  default     = 365
}

variable "container_insights" {
  description = "Container Insights: enabled, or enhanced for per-container metrics (costs more)."
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "enhanced"], var.container_insights)
    error_message = "container_insights is enabled or enhanced; it is never off here."
  }
}
