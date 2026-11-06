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

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT."
  }
}

variable "default_action" {
  description = "aws_wafv2_web_acl's default_action: allow = {} or block = {}, for a request no rule decides."
  type = object({
    allow = optional(object({}))
    block = optional(object({}))
  })

  validation {
    condition     = (var.default_action.allow != null) != (var.default_action.block != null)
    error_message = "default_action is allow or block, not both."
  }
}

variable "rule" {
  description = "aws_wafv2_web_acl's rule blocks: name, priority, action (allow, block or count) for a rate-based statement or override_action (none or count) for a managed rule group, the statement, and its visibility_config."
  type = list(object({
    name     = string
    priority = number
    action = optional(object({
      allow = optional(object({}))
      block = optional(object({}))
      count = optional(object({}))
    }))
    override_action = optional(object({
      none  = optional(object({}))
      count = optional(object({}))
    }))
    statement = object({
      managed_rule_group_statement = optional(object({
        name        = string
        vendor_name = string
      }))
      rate_based_statement = optional(object({
        limit              = number
        aggregate_key_type = string
      }))
    })
    visibility_config = object({
      cloudwatch_metrics_enabled = bool
      metric_name                = string
      sampled_requests_enabled   = bool
    })
  }))

  validation {
    condition     = length(distinct([for r in var.rule : r.name])) == length(var.rule) && length(distinct([for r in var.rule : r.priority])) == length(var.rule)
    error_message = "Each rule has its own name and its own priority."
  }

  validation {
    condition     = alltrue([for r in var.rule : (r.statement.managed_rule_group_statement != null) != (r.statement.rate_based_statement != null)])
    error_message = "A rule's statement is one managed_rule_group_statement or one rate_based_statement."
  }

  validation {
    condition = alltrue([
      for r in var.rule : r.statement.managed_rule_group_statement != null
      ? r.action == null && try(length(compact([r.override_action.none == null ? "" : "none", r.override_action.count == null ? "" : "count"])) == 1, false)
      : r.override_action == null && try(length(compact([r.action.allow == null ? "" : "allow", r.action.block == null ? "" : "block", r.action.count == null ? "" : "count"])) == 1, false)
    ])
    error_message = "A managed rule group takes override_action (none or count); any other rule takes action (allow, block or count). Each names exactly one."
  }

  validation {
    condition     = alltrue([for r in var.rule : r.statement.rate_based_statement == null || try(r.statement.rate_based_statement.limit >= 100 && contains(["IP", "FORWARDED_IP"], r.statement.rate_based_statement.aggregate_key_type), false)])
    error_message = "A rate_based_statement's limit is at least 100 requests per five minutes, and its aggregate_key_type IP or FORWARDED_IP."
  }
}

variable "visibility_config" {
  description = "aws_wafv2_web_acl's own visibility_config."
  type = object({
    cloudwatch_metrics_enabled = bool
    metric_name                = string
    sampled_requests_enabled   = bool
  })
}

variable "log_bucket_arn" {
  description = "The WAF log bucket (aws-waf-logs-...), from the logging stack."
  type        = string
}

variable "resource_arns" {
  description = "Load balancer ARNs to protect, for a REGIONAL web ACL. A distribution names its web ACL itself."
  type        = list(string)
  default     = []

  validation {
    condition     = var.scope == "REGIONAL" || length(var.resource_arns) == 0
    error_message = "A CLOUDFRONT web ACL is named by its distribution's web_acl_id; it takes no resource_arns."
  }
}
