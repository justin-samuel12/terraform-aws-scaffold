variable "config_dir" {
  description = "The folder of role files, one <role>.yml each, with shared policies in policies/<name>.yml; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
