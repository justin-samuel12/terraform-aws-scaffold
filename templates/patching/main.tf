module "patch_management" {
  source = "../../modules/patch-management"

  environment         = var.environment
  patch_baselines     = local.ready ? local.patch_baselines : {}
  maintenance_windows = local.ready ? local.maintenance_windows : {}
}
