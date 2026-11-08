variable "account_id" {
  description = "The shared account the state bucket lives in: the hub's account_id in the primary region's file."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id is the 12-digit account the bucket is created in."
  }
}

variable "region" {
  description = "The bucket's region: state.region in config/global.yml."
  type        = string
}

variable "bucket" {
  description = "The bucket's name: state.bucket in config/global.yml."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket))
    error_message = "bucket is a valid S3 bucket name: 3 to 63 lowercase letters, digits, dots and hyphens."
  }
}

variable "replica_region" {
  description = "A second region to replicate state to, so state survives a regional outage: state.replica_region in config/global.yml. null: no replica."
  type        = string
  default     = null
}

variable "profile" {
  description = "The AWS profile for the shared account, from this machine's config; null: whatever credentials are active."
  type        = string
  default     = null
}

variable "account_prefixes" {
  description = "Account ID -> the state keys its environments use, their stored plans and their apply claims, as S3 key patterns (us-east-2/production/*, plans/us-east-2/production/*, applied/us-east-2/production/*). Each other account may read and write only those. Empty in single-account mode."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for a in keys(var.account_prefixes) : can(regex("^[0-9]{12}$", a))])
    error_message = "account_prefixes is keyed by 12-digit account IDs."
  }
}
