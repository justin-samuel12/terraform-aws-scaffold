variable "config_dir" {
  description = "The folder of distribution files, one <name>.yml each; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
