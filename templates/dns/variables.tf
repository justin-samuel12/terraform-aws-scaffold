variable "config_path" {
  description = "The repository's config folder (global.yml and one <region>.yml per region); null: config/ at the repository root. Stacks pass their own, tests a fixture."
  type        = string
  default     = null
}
