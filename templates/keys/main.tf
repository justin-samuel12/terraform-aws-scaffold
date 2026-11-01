module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "kms_key" {
  source = "../../modules/kms-key"

  environment     = var.environment
  purposes        = { for p, services in local.purposes : p => toset(services) }
  replica_regions = local.replica_regions
}
