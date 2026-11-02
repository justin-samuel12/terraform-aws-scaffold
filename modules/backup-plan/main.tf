data "aws_partition" "current" {}

resource "aws_backup_vault" "vault" {
  name        = var.environment
  kms_key_arn = var.kms_key_arn

  tags = { Name = var.environment }
}

# No backup is deleted before it is a week old; nothing is kept past ten years. Governance mode lets a principal allowed to bypass
# the lock remove it; compliance mode lets nobody, and becomes permanent after changeable_for_days -- docs/data.md.
resource "aws_backup_vault_lock_configuration" "vault" {
  backup_vault_name   = aws_backup_vault.vault.name
  min_retention_days  = 7
  max_retention_days  = 3650
  changeable_for_days = var.vault_lock == "compliance" ? 3 : null
}

resource "aws_backup_vault" "copy" {
  count = var.copy == null ? 0 : 1

  region      = var.copy.region
  name        = var.environment
  kms_key_arn = var.copy.kms_key_arn

  tags = { Name = var.environment }
}

resource "aws_backup_vault_lock_configuration" "copy" {
  count = var.copy == null ? 0 : 1

  region              = var.copy.region
  backup_vault_name   = aws_backup_vault.copy[0].name
  min_retention_days  = 7
  max_retention_days  = 3650
  changeable_for_days = var.vault_lock == "compliance" ? 3 : null
}

resource "aws_backup_plan" "plan" {
  name = var.environment

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.vault.name
    schedule          = "cron(0 7 * * ? *)"
    start_window      = 60
    completion_window = 360

    lifecycle {
      delete_after = var.daily_retention_days
    }

    dynamic "copy_action" {
      for_each = var.copy == null ? [] : [1]
      content {
        destination_vault_arn = aws_backup_vault.copy[0].arn
        lifecycle {
          delete_after = var.daily_retention_days
        }
      }
    }
  }

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.vault.name
    schedule          = "cron(0 8 1 * ? *)"
    start_window      = 60
    completion_window = 720

    lifecycle {
      delete_after = var.monthly_retention_days
    }

    dynamic "copy_action" {
      for_each = var.copy == null ? [] : [1]
      content {
        destination_vault_arn = aws_backup_vault.copy[0].arn
        lifecycle {
          delete_after = var.monthly_retention_days
        }
      }
    }
  }

  tags = { Name = var.environment }
}

resource "aws_iam_role" "backup" {
  name = "backup-${var.environment}"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "backup.amazonaws.com" } }]
  })

  tags = { Name = "backup-${var.environment}" }
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "service-role/AWSBackupServiceRolePolicyForBackup",
    "service-role/AWSBackupServiceRolePolicyForRestores",
    "AWSBackupServiceRolePolicyForS3Backup",
    "AWSBackupServiceRolePolicyForS3Restore",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

# A resource joins the plan by tagging itself Backup = standard, from its own stack.
resource "aws_backup_selection" "tagged" {
  name         = "${var.environment}-tagged"
  plan_id      = aws_backup_plan.plan.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "standard"
  }

  depends_on = [aws_iam_role_policy_attachment.backup]
}
