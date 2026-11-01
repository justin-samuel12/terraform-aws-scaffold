module "network" {
  source = "../../../../templates/network"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
