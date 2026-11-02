variable "environment" {
  description = "The environment whose resources are backed up; the vault and plan are named after it."
  type        = string
}

variable "kms_key_arn" {
  description = "The environment's backup key, in this region."
  type        = string
}

variable "daily_retention_days" {
  description = "Days each daily backup is kept."
  type        = number
  default     = 35

  validation {
    condition     = var.daily_retention_days >= 7
    error_message = "daily_retention_days is at least 7."
  }
}

variable "monthly_retention_days" {
  description = "Days each monthly backup is kept."
  type        = number
  default     = 365
}

variable "copy" {
  description = "Copy every backup to a vault in another region, encrypted with that region's replica of the backup key; null for no copies."
  type = object({
    region      = string
    kms_key_arn = string
  })
  default = null
}

variable "vault_lock" {
  description = "governance: no backup is deleted before min_retention_days except by a principal allowed to bypass the lock. compliance: nobody, ever, can; it becomes permanent 3 days after the first apply, and cannot be undone."
  type        = string
  default     = "governance"

  validation {
    condition     = contains(["governance", "compliance"], var.vault_lock)
    error_message = "vault_lock is governance or compliance."
  }
}
