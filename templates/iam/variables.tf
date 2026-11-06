variable "config_dir" {
  description = "The folder holding role/<name>.yml, policy/<name>.yml and instance-profile/<name>.yml; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
