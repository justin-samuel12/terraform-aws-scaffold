variable "environment" {
  description = "The environment whose resources are backed up; the backup role is backup-<environment>."
  type        = string
}

variable "backup_vaults" {
  description = "Vault name -> its aws_backup_vault arguments (region, kms_key_arn, tags) and its aws_backup_vault_lock_configuration (lock_configuration: min_retention_days, max_retention_days, changeable_for_days). Every vault is locked."
  type = map(object({
    region      = optional(string)
    kms_key_arn = string
    tags        = optional(map(string), {})
    lock_configuration = object({
      min_retention_days  = number
      max_retention_days  = optional(number)
      changeable_for_days = optional(number)
    })
  }))
  default = {}

  validation {
    condition     = alltrue([for v in values(var.backup_vaults) : v.lock_configuration.min_retention_days >= 1 && try(v.lock_configuration.max_retention_days >= v.lock_configuration.min_retention_days, v.lock_configuration.max_retention_days == null)])
    error_message = "lock_configuration.min_retention_days is at least 1, and max_retention_days no less than it."
  }
}

variable "backup_plans" {
  description = "Plan name -> its aws_backup_plan rule list and tags. target_vault_name is a vault in backup_vaults; copy_action.destination_vault_arn is one by name, or any vault's ARN. Each plan selects the resources tagged Backup = standard."
  type = map(object({
    rule = list(object({
      rule_name                    = string
      target_vault_name            = string
      schedule                     = optional(string)
      schedule_expression_timezone = optional(string)
      start_window                 = optional(number)
      completion_window            = optional(number)
      enable_continuous_backup     = optional(bool)
      recovery_point_tags          = optional(map(string))
      lifecycle = optional(object({
        delete_after       = optional(number)
        cold_storage_after = optional(number)
      }))
      copy_action = optional(list(object({
        destination_vault_arn = string
        lifecycle = optional(object({
          delete_after       = optional(number)
          cold_storage_after = optional(number)
        }))
      })), [])
    }))
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue(flatten([for p in values(var.backup_plans) : [for r in p.rule : contains(keys(var.backup_vaults), r.target_vault_name)]]))
    error_message = "A rule's target_vault_name is a vault in backup_vaults."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.backup_plans) : [for r in p.rule : [for c in r.copy_action : contains(keys(var.backup_vaults), c.destination_vault_arn) || startswith(c.destination_vault_arn, "arn:")]]]))
    error_message = "copy_action.destination_vault_arn is a vault in backup_vaults by name, or a vault's ARN."
  }
}

variable "role_boundary" {
  description = "Where every IAM role, instance profile and policy this module creates goes, and the permission boundary each role carries: the deploying duty's, so a role can never do more than the pipeline lets that duty do. null: path / and no boundary."
  type = object({
    path                 = string
    permissions_boundary = string
  })
  default = null
}
