module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "backup_plan" {
  source = "../../modules/backup-plan"

  environment   = var.environment
  backup_vaults = !local.ready ? {} : { for name, v in local.vaults : name => merge(v, { kms_key_arn = try(data.aws_kms_key.vaults[name].arn, v.kms_key_arn) }) }
  backup_plans  = local.ready ? local.plans : {}

  role_boundary = module.role_boundary.role_boundary
}

module "role_boundary" {
  source = "../../modules/role-boundary"

  duties_file = "${path.module}/../duties.yml"
}
