variable "region" {
  description = "The region whose log buckets these are."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be an AWS region name, such as us-east-2."
  }
}

variable "config_dir" {
  description = "The folder of log bucket files, lb-logs.yml and aws-waf-logs.yml; null = the stack's config/ folder. Tests point it at their own."
  type        = string
  default     = null
}
