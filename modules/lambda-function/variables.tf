variable "name" {
  description = "The function's name; its role and log group are named from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,63}$", var.name))
    error_message = "name is lowercase letters, digits and hyphens."
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

variable "memory" {
  description = "Memory in MB; CPU scales with it."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Seconds before a run is stopped."
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
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
  description = "Extra permissions beyond writing its own logs."
  type = list(object({
    actions   = list(string)
    resources = list(string)
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.statements : !(contains(s.actions, "*") && contains(s.resources, "*"))])
    error_message = "No statement may allow every action on every resource."
  }
}

variable "schedule" {
  description = "An EventBridge schedule, such as rate(1 day) or cron(0 6 * * ? *); null for none."
  type        = string
  default     = null

  validation {
    condition     = var.schedule == null || can(regex("^(rate|cron)\\(.+\\)$", coalesce(var.schedule, "-")))
    error_message = "schedule is rate(...) or cron(...)."
  }
}

variable "log_retention_days" {
  description = "How long the function's logs are kept."
  type        = number
  default     = 365
}

variable "queue" {
  description = "An SQS queue the function takes its messages from, in batches; failed messages go back to the queue on their own, the rest are deleted. null for none."
  type = object({
    arn                                = string
    batch_size                         = optional(number, 10)
    maximum_batching_window_in_seconds = optional(number, 0)
  })
  default = null

  validation {
    condition     = var.queue == null || try(var.queue.batch_size >= 1 && var.queue.batch_size <= 10000 && var.queue.maximum_batching_window_in_seconds >= 0 && var.queue.maximum_batching_window_in_seconds <= 300, false)
    error_message = "queue.batch_size is 1 to 10000, and maximum_batching_window_in_seconds 0 to 300."
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
