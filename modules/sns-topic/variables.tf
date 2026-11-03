variable "name" {
  description = "The topic's name; a FIFO topic gets .fifo added."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,251}$", var.name))
    error_message = "name is letters, digits, hyphens and underscores."
  }
}

variable "kms_key_arn" {
  description = "The environment's messages key; every message is encrypted with it."
  type        = string
}

variable "fifo" {
  description = "A FIFO topic, delivering in order to FIFO queues only."
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "FIFO only: a message's body is its deduplication ID."
  type        = bool
  default     = false
}

variable "subscriptions" {
  description = "Name -> where the topic delivers: an SQS queue or Lambda function by ARN, an HTTPS URL, or an email address (confirmed by its owner)."
  type = map(object({
    protocol             = string
    endpoint             = string
    raw_message_delivery = optional(bool, false)
    filter_policy        = optional(string)
    filter_policy_scope  = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.subscriptions) : contains(["sqs", "lambda", "https", "email", "email-json"], s.protocol)])
    error_message = "A subscription's protocol is sqs, lambda, https, email or email-json; plain http would send messages unencrypted."
  }

  validation {
    condition     = alltrue([for s in values(var.subscriptions) : !s.raw_message_delivery || contains(["sqs", "https"], s.protocol)])
    error_message = "raw_message_delivery is for sqs and https subscriptions only."
  }
}

variable "publisher_accounts" {
  description = "Other accounts whose roles may publish to the topic; their own IAM must allow it too."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.publisher_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "publisher_accounts are 12-digit account IDs."
  }
}

variable "publisher_services" {
  description = "AWS services that publish for this account, without .amazonaws.com (cloudwatch for alarms, events for EventBridge)."
  type        = set(string)
  default     = []
}
