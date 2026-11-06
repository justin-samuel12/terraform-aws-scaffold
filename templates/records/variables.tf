variable "environment" {
  description = "The environment these records belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "config_dir" {
  description = "The folder of record files, one <name>.yml each; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
