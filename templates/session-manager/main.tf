# Sessions get a key of their own: only Session Manager may use it, for this account.
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

  kms_key_arn          = module.kms_key.arns["sessions"]
  idle_timeout_minutes = local.settings.idle_timeout_minutes
  max_session_minutes  = local.settings.max_session_minutes
  log_retention_days   = local.settings.retention_in_days

  create_default_host_role = var.region == module.ip_plan.primary_region
}
