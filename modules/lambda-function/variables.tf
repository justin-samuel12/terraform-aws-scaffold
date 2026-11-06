variable "name" {
  description = "The function's name; its role and log group are named from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,40}$", var.name))
    error_message = "name is up to 41 lowercase letters, digits and hyphens: its role, lambda-<name>-<region>, must fit IAM's 64 characters."
  }
}

variable "source_dir" {
  description = "The folder holding the function's code, zipped as it is."
  type        = string
}

variable "runtime" {
  description = "A Lambda runtime, such as python3.12 or nodejs20.x."
  type        = string
}

variable "handler" {
  description = "The entry point, such as app.handler."
  type        = string
}

variable "memory_size" {
  description = "Memory in MB; CPU scales with it. null takes the provider's default (128)."
  type        = number
  default     = null
}

variable "timeout" {
  description = "Seconds before a run is stopped; null takes the provider's default (3)."
  type        = number
  default     = null

  validation {
    condition     = var.timeout == null || try(var.timeout >= 1 && var.timeout <= 900, false)
    error_message = "timeout is 1 to 900 seconds."
  }
}

variable "environment" {
  description = "Environment variables. Never secrets: the AWS provider does not hide these in plans, so a function reads its secrets from SSM or Secrets Manager when it runs."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.environment) : !can(regex("(?i)(password|secret|token|private_key|api_key|credential)", k))])
    error_message = "Environment variables never hold secrets: read them from SSM Parameter Store or Secrets Manager at run time (SKILLS.md)."
  }
}

variable "statements" {
  description = "Extra permissions beyond writing its own logs, as in aws_iam_policy_document."
  type = list(object({
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.statements : contains(["Allow", "Deny"], s.effect) && !(contains(s.actions, "*") && contains(s.resources, "*"))])
    error_message = "A statement's effect is Allow or Deny, and none may allow every action on every resource."
  }
}

variable "schedule_expression" {
  description = "An EventBridge rule's schedule_expression, such as rate(1 day) or cron(0 6 * * ? *); null for none."
  type        = string
  default     = null

  validation {
    condition     = var.schedule_expression == null || can(regex("^(rate|cron)\\(.+\\)$", coalesce(var.schedule_expression, "-")))
    error_message = "schedule_expression is rate(...) or cron(...)."
  }
}

variable "retention_in_days" {
  description = "How long the function's log group keeps its logs."
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days is one of CloudWatch Logs' periods: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}

variable "event_source_mapping" {
  description = "The arguments of aws_lambda_event_source_mapping for an SQS queue the function takes its messages from; null arguments take the provider's defaults. null for none."
  type = object({
    event_source_arn                   = string
    batch_size                         = optional(number)
    maximum_batching_window_in_seconds = optional(number)
    function_response_types            = optional(list(string))
  })
  default = null

  validation {
    condition     = var.event_source_mapping == null || try((var.event_source_mapping.batch_size == null || (var.event_source_mapping.batch_size >= 1 && var.event_source_mapping.batch_size <= 10000)) && (var.event_source_mapping.maximum_batching_window_in_seconds == null || (var.event_source_mapping.maximum_batching_window_in_seconds >= 0 && var.event_source_mapping.maximum_batching_window_in_seconds <= 300)), false)
    error_message = "event_source_mapping.batch_size is 1 to 10000, and maximum_batching_window_in_seconds 0 to 300."
  }
}

variable "topics" {
  description = "SNS topics the function subscribes to itself, by name: each topic's ARN, and an optional filter policy (JSON) and its scope."
  type = map(object({
    arn                 = string
    filter_policy       = optional(string)
    filter_policy_scope = optional(string)
  }))
  default = {}
}
