variable "environment" {
  description = "The environment whose Windows servers join the domain: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "config_dir" {
  description = "The folder of association files, one <name>.yml each with the aws_ssm_association arguments; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
