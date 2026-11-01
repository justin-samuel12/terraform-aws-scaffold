variable "name" {
  description = "The bucket's name, globally unique. A WAF log bucket must start with aws-waf-logs-."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be a valid S3 bucket name."
  }
}

variable "delivers" {
  description = "Which AWS service writes to it: load-balancer (access logs) or waf (web ACL logs)."
  type        = string

  validation {
    condition     = contains(["load-balancer", "waf"], var.delivers)
    error_message = "delivers must be load-balancer or waf."
  }
}

variable "retention_days" {
  description = "Days a log is kept before it expires; an overwritten or deleted log's old version is kept 30 days more."
  type        = number
  default     = 365

  validation {
    condition     = var.retention_days >= 30
    error_message = "retention_days must be at least 30."
  }
}
