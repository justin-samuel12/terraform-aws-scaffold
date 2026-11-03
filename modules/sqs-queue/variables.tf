variable "name" {
  description = "The queue's name; a FIFO queue gets .fifo added, and its dead-letter queue is <name>-dlq."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,70}$", var.name))
    error_message = "name is up to 70 letters, digits, hyphens and underscores (the dead-letter queue and .fifo need the rest of SQS's 80)."
  }
}

variable "kms_key_arn" {
  description = "The environment's messages key; every message is encrypted with it."
  type        = string
}

variable "fifo" {
  description = "A FIFO queue: exactly-once, in order within each message group."
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "FIFO only: a message's body is its deduplication ID."
  type        = bool
  default     = false
}

variable "visibility_timeout_seconds" {
  description = "How long a received message stays hidden before another consumer may take it. For a Lambda consumer, at least six times its timeout."
  type        = number
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds is 0 to 43200 (12 hours)."
  }
}

variable "message_retention_seconds" {
  description = "How long an unread message is kept."
  type        = number
  default     = 345600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds is 60 to 1209600 (14 days)."
  }
}

variable "delay_seconds" {
  description = "How long every new message waits before it can be received."
  type        = number
  default     = 0

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "delay_seconds is 0 to 900."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling: how long a receive waits for a message, so empty receives are rare (and cheap)."
  type        = number
  default     = 20

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds is 0 to 20."
  }
}

variable "max_receive_count" {
  description = "Receives before a message that keeps failing moves to the dead-letter queue."
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1000
    error_message = "max_receive_count is 1 to 1000."
  }
}

variable "topic_arns" {
  description = "SNS topics that deliver into the queue."
  type        = set(string)
  default     = []
}

variable "sender_accounts" {
  description = "Other accounts whose roles may send to the queue; their own IAM must allow it too."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.sender_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "sender_accounts are 12-digit account IDs."
  }
}

variable "consumer_accounts" {
  description = "Other accounts whose roles may receive and delete the queue's messages; their own IAM must allow it too."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.consumer_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "consumer_accounts are 12-digit account IDs."
  }
}
