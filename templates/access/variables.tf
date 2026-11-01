variable "environment" {
  description = "The environment these access documents belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "config_dir" {
  description = "The folder of tunnel files, one <name>.yml each; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
