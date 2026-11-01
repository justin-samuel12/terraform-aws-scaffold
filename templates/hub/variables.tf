variable "region" {
  description = "The AWS region this hub is built in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }

  validation {
    condition     = contains(keys(module.ip_plan.networks), "shared/${var.region}")
    error_message = "There is no config/shared/${var.region}.yml with a hub; add it first."
  }
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
