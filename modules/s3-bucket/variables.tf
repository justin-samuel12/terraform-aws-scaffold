variable "name" {
  description = "The bucket's name, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name is 3 to 63 lowercase letters, digits and hyphens."
  }
}

variable "kms_key_arn" {
  description = "The environment's data key; every object is encrypted with it."
  type        = string
}

variable "tags" {
  description = "The bucket's tags; Backup = standard puts it in the environment's AWS Backup plan. Name is the bucket's name."
  type        = map(string)
  default     = {}
}

variable "object_lock_enabled" {
  description = "aws_s3_bucket's object_lock_enabled: whether the bucket can hold locked objects. Set only when the bucket is created."
  type        = bool
  default     = false
}

variable "object_lock_configuration" {
  description = "aws_s3_bucket_object_lock_configuration's rule.default_retention: mode GOVERNANCE (admins can override) or COMPLIANCE (no one can), and days or years. null for none."
  type = object({
    rule = object({
      default_retention = object({
        mode  = string
        days  = optional(number)
        years = optional(number)
      })
    })
  })
  default = null

  validation {
    condition     = var.object_lock_configuration == null || try(contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_configuration.rule.default_retention.mode) && (var.object_lock_configuration.rule.default_retention.days == null) != (var.object_lock_configuration.rule.default_retention.years == null), false)
    error_message = "default_retention.mode is GOVERNANCE or COMPLIANCE, with days or years."
  }

  validation {
    condition     = var.object_lock_configuration == null || var.object_lock_enabled
    error_message = "object_lock_configuration needs object_lock_enabled."
  }
}

variable "lifecycle_rule" {
  description = "aws_s3_bucket_lifecycle_configuration's rules: id, status, filter (prefix; left out, the whole bucket), expiration (days), noncurrent_version_expiration (noncurrent_days), abort_incomplete_multipart_upload (days_after_initiation). None, no lifecycle configuration."
  type = list(object({
    id     = string
    status = string
    filter = optional(object({
      prefix = optional(string)
    }))
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
    condition     = alltrue([for r in var.lifecycle_rule : contains(["Enabled", "Disabled"], r.status)])
    error_message = "A lifecycle rule's status is Enabled or Disabled."
  }
}

variable "cors_rule" {
  description = "aws_s3_bucket_cors_configuration's cors_rule list, for browsers uploading or reading directly. None, no CORS configuration."
  type = list(object({
    id              = optional(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.cors_rule : !contains(c.allowed_origins, "*")])
    error_message = "CORS origins are named; * would let any website use the bucket from a visitor's browser."
  }
}

variable "policy_statements" {
  description = "Extra bucket policy statements, such as the one a CloudFront distribution's output gives."
  type        = list(any)
  default     = []
}
