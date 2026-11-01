variable "region" {
  description = "The region the web ACLs protect load balancers in."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of web ACL files, one <name>.yml each; null = the stack's own folder. Tests point it at their own."
  type        = string
  default     = null
}
