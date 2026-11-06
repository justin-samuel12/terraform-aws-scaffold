variable "environment" {
  description = "The environment the instances patched belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "config_dir" {
  description = "The folder holding patch-baseline/<name>.yml and maintenance-window/<name>.yml; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
