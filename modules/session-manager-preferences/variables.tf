variable "kms_key_arn" {
  description = "The key every session's data is encrypted with."
  type        = string
}

variable "idle_timeout_minutes" {
  description = "A session with no activity this long is closed."
  type        = number
  default     = 20

  validation {
    condition     = var.idle_timeout_minutes >= 1 && var.idle_timeout_minutes <= 60
    error_message = "idle_timeout_minutes is 1 to 60."
  }
}

variable "max_session_minutes" {
  description = "No session lasts longer than this."
  type        = number
  default     = 480
}

variable "log_retention_days" {
  description = "How long session logs are kept."
  type        = number
  default     = 365
}

variable "create_default_host_role" {
  description = "Create the account's Default Host Management role. It is account-wide, so only the primary region's stack creates it; every region's setting points at it."
  type        = bool
  default     = false
}
