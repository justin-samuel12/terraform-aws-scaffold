variable "environment" {
  description = "The environment whose plan and apply roles this stack creates, in that environment's account."
  type        = string
}

variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region). Stacks pass their own, tests a fixture."
  type        = string
}
