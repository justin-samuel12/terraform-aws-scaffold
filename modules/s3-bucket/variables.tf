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

variable "noncurrent_days" {
  description = "Days an overwritten or deleted object's old version is kept."
  type        = number
  default     = 90
}

variable "expire_days" {
  description = "Days before current objects expire; null to keep them."
  type        = number
  default     = null
}

variable "backup" {
  description = "Back the bucket up with the environment's AWS Backup plan."
  type        = bool
  default     = false
}

variable "object_lock" {
  description = "Objects that must not change or be deleted for a time: GOVERNANCE (admins can override) or COMPLIANCE (no one can), and for how many days. Set only when the bucket is created."
  type = object({
    mode = string
    days = number
  })
  default = null

  validation {
    condition     = var.object_lock == null || try(contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock.mode) && var.object_lock.days >= 1, false)
    error_message = "object_lock.mode is GOVERNANCE or COMPLIANCE, and days at least 1."
  }
}

variable "cors" {
  description = "CORS rules, for browsers uploading or reading directly."
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default = []

  validation {
    condition     = alltrue([for c in var.cors : !contains(c.allowed_origins, "*")])
    error_message = "CORS origins are named; * would let any website use the bucket from a visitor's browser."
  }
}

variable "policy_statements" {
  description = "Extra bucket policy statements, such as the one a CloudFront distribution's output gives."
  type        = list(any)
  default     = []
}
