variable "config_dir" {
  description = "The folder of the stack's files: one <name>.yml per distribution in distribution/, and one per CLOUDFRONT web ACL in web-acl/; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
