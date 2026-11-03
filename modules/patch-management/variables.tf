variable "environment" {
  description = "The environment patched: its instances carry the tag PatchGroup = <environment>."
  type        = string
}

variable "schedule" {
  description = "When the maintenance window opens, as cron(...) in UTC."
  type        = string
  default     = "cron(0 7 ? * SUN *)"

  validation {
    condition     = can(regex("^cron\\(.+\\)$", var.schedule))
    error_message = "schedule is cron(...)."
  }
}

variable "duration_hours" {
  description = "How long the window stays open."
  type        = number
  default     = 3
}

variable "approve_after_days" {
  description = "Days a released patch waits before it is approved, so it can be tried elsewhere first."
  type        = number
  default     = 7

  validation {
    condition     = var.approve_after_days >= 0 && var.approve_after_days <= 100
    error_message = "approve_after_days is 0 to 100."
  }
}
