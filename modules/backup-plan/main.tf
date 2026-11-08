resource "aws_backup_vault" "vaults" {
  for_each = var.backup_vaults

  region      = each.value.region
  name        = each.key
  kms_key_arn = each.value.kms_key_arn

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${trimprefix(each.key, "${local.environment_tag}-")}" })
}

resource "aws_backup_vault_lock_configuration" "vaults" {
  for_each = var.backup_vaults

  region              = each.value.region
  backup_vault_name   = aws_backup_vault.vaults[each.key].name
  min_retention_days  = each.value.lock_configuration.min_retention_days
  max_retention_days  = each.value.lock_configuration.max_retention_days
  changeable_for_days = each.value.lock_configuration.changeable_for_days
}

resource "aws_backup_plan" "plans" {
  for_each = var.backup_plans

  name = each.key

  dynamic "rule" {
    for_each = each.value.rule
    content {
      rule_name                    = rule.value.rule_name
      target_vault_name            = aws_backup_vault.vaults[rule.value.target_vault_name].name
      schedule                     = rule.value.schedule
      schedule_expression_timezone = rule.value.schedule_expression_timezone
      start_window                 = rule.value.start_window
      completion_window            = rule.value.completion_window
      enable_continuous_backup     = rule.value.enable_continuous_backup
      recovery_point_tags          = rule.value.recovery_point_tags

      dynamic "lifecycle" {
        for_each = rule.value.lifecycle == null ? [] : [rule.value.lifecycle]
        content {
          delete_after       = lifecycle.value.delete_after
          cold_storage_after = lifecycle.value.cold_storage_after
        }
      }

      dynamic "copy_action" {
        for_each = rule.value.copy_action
        content {
          destination_vault_arn = try(aws_backup_vault.vaults[copy_action.value.destination_vault_arn].arn, copy_action.value.destination_vault_arn)

          dynamic "lifecycle" {
            for_each = copy_action.value.lifecycle == null ? [] : [copy_action.value.lifecycle]
            content {
              delete_after       = lifecycle.value.delete_after
              cold_storage_after = lifecycle.value.cold_storage_after
            }
          }
        }
      }
    }
  }

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${trimprefix(each.key, "${local.environment_tag}-")}" })
}

resource "aws_iam_role" "backup" {
  count = length(var.backup_plans) > 0 ? 1 : 0

  name                 = "backup-${var.environment}"
  path                 = try(var.role_boundary.path, "/")
  permissions_boundary = try(var.role_boundary.permissions_boundary, null)

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "backup.amazonaws.com" } }]
  })

  tags = { Name = "${local.name_prefix}backup" }
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = length(var.backup_plans) > 0 ? toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
    "AWSBackupServiceRolePolicyForS3Backup",
    "AWSBackupServiceRolePolicyForS3Restore",
  ]) : toset([])

  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

resource "aws_backup_selection" "tagged" {
  for_each = var.backup_plans

  name         = "${each.key}-tagged"
  plan_id      = aws_backup_plan.plans[each.key].id
  iam_role_arn = aws_iam_role.backup[0].arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "standard"
  }

  depends_on = [aws_iam_role_policy_attachment.backup]
}
