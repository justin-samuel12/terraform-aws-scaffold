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

variable "tags" {
  description = "The bucket's tags; Name is always its name."
  type        = map(string)
  default     = {}
}

variable "rule" {
  description = "The rule list of the bucket's aws_s3_bucket_lifecycle_configuration: id, status, filter.prefix, expiration.days, noncurrent_version_expiration.noncurrent_days, abort_incomplete_multipart_upload.days_after_initiation. Empty: no lifecycle, logs are kept."
  type = list(object({
    id     = string
    status = string
    filter = optional(object({
      prefix = optional(string, "")
    }), {})
    expiration = optional(object({
      days = number
    }))
    noncurrent_version_expiration = optional(object({
      noncurrent_days = number
    }))
    abort_incomplete_multipart_upload = optional(object({
      days_after_initiation = number
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.rule : contains(["Enabled", "Disabled"], r.status)])
    error_message = "A rule's status is Enabled or Disabled."
  }
}
