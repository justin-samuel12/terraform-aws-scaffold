variable "region" {
  description = "The region the registry is in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of repository files, <name>.yml each, and the registry's replication-configuration/<name>.yml; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
