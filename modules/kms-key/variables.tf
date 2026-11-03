variable "environment" {
  description = "The environment the keys belong to; aliases are alias/<environment>-<purpose>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "environment is lowercase letters, digits and hyphens."
  }
}

variable "purposes" {
  description = "Purpose -> which AWS services may use the key, without .amazonaws.com (rds, elasticfilesystem, backup, secretsmanager, ec2, logs)."
  type        = map(set(string))

  validation {
    condition     = alltrue([for p in keys(var.purposes) : can(regex("^[a-z][a-z0-9-]*$", p))]) && alltrue([for s in var.purposes : length(s) > 0])
    error_message = "Purposes are lowercase names, each used by at least one service."
  }
}

variable "replica_regions" {
  description = "Regions each key is replicated to (multi-Region keys), so copies and restores there use the same key."
  type        = set(string)
  default     = []
}

variable "caller_accounts" {
  description = "Purpose -> other accounts that may use the key, still only through its named services; their own IAM must allow it too."
  type        = map(set(string))
  default     = {}

  validation {
    condition     = alltrue(flatten([for accounts in values(var.caller_accounts) : [for a in accounts : can(regex("^[0-9]{12}$", a))]]))
    error_message = "caller_accounts are 12-digit account IDs."
  }
}

variable "service_principals" {
  description = "Purpose -> AWS services that use the key themselves, for this account only, without .amazonaws.com (sns, events, cloudwatch)."
  type        = map(set(string))
  default     = {}
}
