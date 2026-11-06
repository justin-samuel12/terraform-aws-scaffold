module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "kms_key" {
  source = "../../modules/kms-key"

  environment = var.environment
  purposes    = { sessions = toset(["ssm"]) }
}

module "session_manager_preferences" {
  source = "../../modules/session-manager-preferences"

  kms_key_arn = module.kms_key.arns["sessions"]
  document    = local.ready ? local.document : null
  log_group   = local.ready ? local.log_group_args : null

  create_default_host_role = var.region == module.ip_plan.primary_region
}
