variable "regions" {
  description = "Every region the account runs in: EBS encryption by default and the access analyzer are regional, so each gets its own."
  type        = set(string)

  validation {
    condition     = length(var.regions) > 0 && alltrue([for r in var.regions : can(regex("^[a-z]{2}-[a-z]+-[0-9]$", r))])
    error_message = "regions must list AWS region names, such as us-east-2."
  }
}
