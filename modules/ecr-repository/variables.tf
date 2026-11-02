variable "repositories" {
  description = "Repository names: lowercase, with optional path segments such as team/app."
  type        = set(string)

  validation {
    condition     = alltrue([for r in var.repositories : can(regex("^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$", r))])
    error_message = "Repository names are lowercase letters and digits, separated by . _ - or /."
  }
}

variable "keep_images" {
  description = "Tagged images kept per repository; older ones expire."
  type        = number
  default     = 30
}

variable "untagged_days" {
  description = "Days an untagged image is kept."
  type        = number
  default     = 14
}

variable "replicate_to" {
  description = "Other regions every repository is copied to, so images survive a regional outage. The registry has one replication setting, so one stack per region sets it."
  type        = set(string)
  default     = []
}

variable "pull_accounts" {
  description = "Other accounts whose roles may pull every repository: each environment's account, when environments have their own."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.pull_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "pull_accounts are 12-digit account IDs."
  }
}
