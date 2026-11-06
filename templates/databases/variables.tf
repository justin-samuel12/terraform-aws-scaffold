variable "environment" {
  description = "The environment these databases belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "blueprints_dir" {
  description = "The folder of database blueprints, <name>/v<n>.yml each; null = blueprints/databases/ at the repository root. Tests point it at their own."
  type        = string
  default     = null
}

variable "config_dir" {
  description = "The folder of database files, one <name>.yml each; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
