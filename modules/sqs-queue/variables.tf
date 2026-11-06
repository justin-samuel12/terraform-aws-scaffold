variable "kms_key_arn" {
  description = "The environment's messages key; every queue is encrypted with it."
  type        = string
}

variable "queues" {
  description = "Queue name (with .fifo for a FIFO queue) -> the arguments of aws_sqs_queue. A null argument takes the provider's default. redrive_policy and redrive_allow_policy take queue ARNs; policy_statements are the queue policy's statements, as in aws_iam_policy_document."
  type = map(object({
    fifo_queue                  = optional(bool)
    content_based_deduplication = optional(bool)
    visibility_timeout_seconds  = optional(number)
    message_retention_seconds   = optional(number)
    delay_seconds               = optional(number)
    receive_wait_time_seconds   = optional(number)
    redrive_policy = optional(object({
      dead_letter_target_arn = string
      max_receive_count      = number
    }))
    redrive_allow_policy = optional(object({
      redrive_permission = string
      source_queue_arns  = optional(list(string))
    }))
    policy_statements = optional(list(object({
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
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for name, q in var.queues : can(regex("^[a-zA-Z0-9_-]{1,80}$", trimsuffix(name, ".fifo"))) && length(name) <= 80 && (coalesce(q.fifo_queue, false) == endswith(name, ".fifo"))])
    error_message = "A queue's name is up to 80 letters, digits, hyphens and underscores, and ends in .fifo exactly when fifo_queue is true."
  }

  validation {
    condition = alltrue([for q in var.queues : alltrue([
      q.visibility_timeout_seconds == null || try(q.visibility_timeout_seconds >= 0 && q.visibility_timeout_seconds <= 43200, false),
      q.message_retention_seconds == null || try(q.message_retention_seconds >= 60 && q.message_retention_seconds <= 1209600, false),
      q.delay_seconds == null || try(q.delay_seconds >= 0 && q.delay_seconds <= 900, false),
      q.receive_wait_time_seconds == null || try(q.receive_wait_time_seconds >= 0 && q.receive_wait_time_seconds <= 20, false),
      q.redrive_policy == null || try(q.redrive_policy.max_receive_count >= 1 && q.redrive_policy.max_receive_count <= 1000, false),
    ])])
    error_message = "visibility_timeout_seconds is 0 to 43200, message_retention_seconds 60 to 1209600, delay_seconds 0 to 900, receive_wait_time_seconds 0 to 20, and redrive_policy.max_receive_count 1 to 1000."
  }

  validation {
    condition     = alltrue([for q in var.queues : q.redrive_allow_policy == null || contains(["allowAll", "denyAll", "byQueue"], try(q.redrive_allow_policy.redrive_permission, ""))])
    error_message = "redrive_allow_policy.redrive_permission is allowAll, denyAll or byQueue."
  }

  validation {
    condition     = alltrue(flatten([for q in var.queues : [for s in q.policy_statements : contains(["Allow", "Deny"], s.effect) && !(contains(s.actions, "*") && contains(s.resources, "*"))]]))
    error_message = "A statement's effect is Allow or Deny, and none may allow every action on every resource."
  }
}
