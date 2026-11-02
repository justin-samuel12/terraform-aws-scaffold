module "patch_management" {
  source = "../../modules/patch-management"

  environment        = var.environment
  schedule           = local.settings.schedule
  duration_hours     = local.settings.duration
  approve_after_days = local.settings.approve_after_days
}
