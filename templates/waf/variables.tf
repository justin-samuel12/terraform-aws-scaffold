variable "environment" {
  description = "The environment the web ACLs belong to: the stack's second folder under live/. Names its web ACLs and finds its load balancers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment must be lowercase letters, digits and hyphens."
  }
}

variable "region" {
  description = "The region the web ACLs protect load balancers in, and whose WAF log bucket they log to."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of web ACL files, one <name>.yml each; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}

variable "scope" {
  description = "REGIONAL for the environment's load balancers; CLOUDFRONT when the cloudfront template builds its distributions' web ACLs, in us-east-1."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT."
  }
}
