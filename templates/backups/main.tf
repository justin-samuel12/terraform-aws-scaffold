module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The environment's backup key and its replica, from the keys stack, found by alias.
data "aws_kms_key" "backup" {
  key_id = "alias/${var.environment}-backup"
}

data "aws_kms_key" "backup_copy" {
  count = local.copy_region == null ? 0 : 1

  region = local.copy_region
  key_id = "alias/${var.environment}-backup"
}

module "backup_plan" {
  source = "../../modules/backup-plan"

  environment            = var.environment
  kms_key_arn            = data.aws_kms_key.backup.arn
  daily_retention_days   = local.settings.daily_retention_days
  monthly_retention_days = local.settings.monthly_retention_days
  vault_lock             = local.settings.vault_lock
  copy                   = local.copy_region == null ? null : { region = local.copy_region, kms_key_arn = data.aws_kms_key.backup_copy[0].arn }
}
