variable "config_dir" {
  description = "The folder of certificate files, one <name>.yml each; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
