# This stack is templates/load-balancers for its environment and region -- docs/architecture.md.
module "load_balancers" {
  source = "../../../../templates/load-balancers"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
