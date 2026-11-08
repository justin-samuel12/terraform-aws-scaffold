variable "kms_key_arn" {
  description = "The key every session's data is encrypted with."
  type        = string
}

variable "document" {
  description = "The SSM-SessionManagerRunShell document's own settings: content.inputs.idleSessionTimeout and maxSessionDuration (minutes, as AWS writes them), and tags. The key, the log group and streaming are fixed. null builds no document, and Session Manager runs on AWS's defaults."
  type = object({
    content = object({
      inputs = object({
        idleSessionTimeout = string
        maxSessionDuration = string
      })
    })
    tags = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.document == null || try(tonumber(var.document.content.inputs.idleSessionTimeout) >= 1 && tonumber(var.document.content.inputs.idleSessionTimeout) <= 60 && tonumber(var.document.content.inputs.maxSessionDuration) >= 1 && tonumber(var.document.content.inputs.maxSessionDuration) <= 1440, false)
    error_message = "idleSessionTimeout is 1 to 60 minutes, maxSessionDuration 1 to 1440."
  }
}

variable "log_group" {
  description = "The /ssm/sessions log group's aws_cloudwatch_log_group arguments: retention_in_days and tags. null builds none."
  type = object({
    retention_in_days = optional(number)
    tags              = optional(map(string), {})
  })
  default = null
}

variable "create_default_host_role" {
  description = "Create the account's Default Host Management role. It is account-wide, so only the primary region's stack creates it; every region's setting points at it."
  type        = bool
  default     = false
}

variable "role_boundary" {
  description = "Where every IAM role, instance profile and policy this module creates goes, and the permission boundary each role carries: the deploying duty's, so a role can never do more than the pipeline lets that duty do. null: path / and no boundary."
  type = object({
    path                 = string
    permissions_boundary = string
  })
  default = null
}
