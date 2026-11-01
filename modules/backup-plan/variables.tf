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
