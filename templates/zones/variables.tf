variable "environment" {
  description = "The environment whose zones these are: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment)) && var.environment != "shared"
    error_message = "environment must be lowercase letters, digits and hyphens, and an environment, not shared (the hubs)."
  }
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
