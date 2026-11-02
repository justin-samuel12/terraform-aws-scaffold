variable "environment" {
  description = "The environment the functions belong to: the stack's second folder under live/. Names every function <environment>-<name>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "config_dir" {
  description = "The folder of function files, one <name>.yml each, with each function's code in src/<name>/; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
