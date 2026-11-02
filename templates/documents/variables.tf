variable "config_dir" {
  description = "The folder of documents, one <name>.yml each with document_type and content; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
