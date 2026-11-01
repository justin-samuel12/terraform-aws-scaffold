variable "config_dir" {
  description = "The folder holding certificates.yml; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
