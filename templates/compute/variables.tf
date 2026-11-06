variable "environment" {
  description = "The environment these servers belong to: the stack's second folder under live/."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "The region the servers run in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of group files, one <group>.yml each; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}

variable "blueprints_dir" {
  description = "The folder of compute blueprints, <name>/v<n>.yml each; null = blueprints/compute/ beside config/. Tests point it at their own."
  type        = string
  default     = null
}

variable "amis_dir" {
  description = "The folder of named images, one data.aws_ami's arguments per file; null = amis/ inside config/. Tests point it at their own."
  type        = string
  default     = null
}

variable "scripts_dir" {
  description = "The folder of shared boot scripts, which user_data: scripts/<name> names; null = scripts/ beside config/. Tests point it at their own."
  type        = string
  default     = null
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
