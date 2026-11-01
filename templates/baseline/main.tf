module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "account_baseline" {
  source = "../../modules/account-baseline"

  regions = local.regions
}
