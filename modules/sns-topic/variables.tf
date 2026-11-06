variable "name" {
  description = "The topic's name, ending in .fifo for a FIFO topic."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,256}$", trimsuffix(var.name, ".fifo")))
    error_message = "name is letters, digits, hyphens and underscores, with .fifo at the end for a FIFO topic."
  }
}

variable "kms_key_arn" {
  description = "The environment's messages key; every message is encrypted with it."
  type        = string
}

variable "fifo_topic" {
  description = "A FIFO topic, delivering in order to FIFO queues only; null takes the provider's default (standard)."
  type        = bool
  default     = null

  validation {
    condition     = coalesce(var.fifo_topic, false) == endswith(var.name, ".fifo")
    error_message = "A topic's name ends in .fifo exactly when fifo_topic is true."
  }
}

variable "content_based_deduplication" {
  description = "FIFO only: a message's body is its deduplication ID."
  type        = bool
  default     = null
}

variable "policy_statements" {
  description = "The topic policy's statements, as in aws_iam_policy_document, after the one refusing anything not over TLS."
  type = list(object({
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    principals = optional(list(object({
      type        = string
      identifiers = list(string)
    })), [])
    condition = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.policy_statements : contains(["Allow", "Deny"], s.effect) && !(contains(s.actions, "*") && contains(s.resources, "*"))])
    error_message = "A statement's effect is Allow or Deny, and none may allow every action on every resource."
  }
}

variable "subscriptions" {
  description = "Key -> the arguments of aws_sns_topic_subscription: an SQS queue by ARN, an HTTPS URL, or an email address (confirmed by its owner)."
  type = map(object({
    protocol             = string
    endpoint             = string
    raw_message_delivery = optional(bool)
    filter_policy        = optional(string)
    filter_policy_scope  = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.subscriptions) : contains(["sqs", "https", "email", "email-json"], s.protocol)])
    error_message = "A subscription's protocol is sqs, https, email or email-json: plain http would send messages unencrypted, and a Lambda function subscribes itself from its own stack."
  }

  validation {
    condition     = alltrue([for s in values(var.subscriptions) : !coalesce(s.raw_message_delivery, false) || contains(["sqs", "https"], s.protocol)])
    error_message = "raw_message_delivery is for sqs and https subscriptions only."
  }
}
