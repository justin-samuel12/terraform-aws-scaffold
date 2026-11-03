variable "environment" {
  description = "The environment these services belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "The region the services run in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of service files, one <service>.yml each; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
