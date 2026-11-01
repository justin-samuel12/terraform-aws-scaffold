variable "config_dir" {
  description = "The folder of function files, one <name>.yml each, with each function's code in src/<name>/; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
