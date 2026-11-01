variable "name" {
  description = "The web ACL's name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,127}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
  }
}

variable "scope" {
  description = "REGIONAL for load balancers, CLOUDFRONT for distributions (created in us-east-1)."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT."
  }
}

variable "managed_rules" {
  description = "AWS managed rule groups, in priority order."
  type        = list(string)
  default     = ["AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet", "AWSManagedRulesAmazonIpReputationList"]

  validation {
    condition     = alltrue([for r in var.managed_rules : can(regex("^AWSManagedRules[A-Za-z0-9]+$", r))])
    error_message = "Managed rules are AWS's rule group names, such as AWSManagedRulesCommonRuleSet."
  }
}

variable "rate_limit" {
  description = "Requests per five minutes from one IP before it is blocked; null for no limit."
  type        = number
  default     = 2000

  validation {
    condition     = var.rate_limit == null || try(var.rate_limit >= 100, false)
    error_message = "rate_limit is at least 100, or null."
  }
}

variable "log_bucket_arn" {
  description = "The WAF log bucket (aws-waf-logs-...), from the logging stack."
  type        = string
}

variable "resource_arns" {
  description = "Load balancers to protect, for a REGIONAL web ACL. A distribution names its web ACL itself."
  type        = list(string)
  default     = []
}
