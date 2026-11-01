# This stack is templates/endpoints for its environment and region -- docs/architecture.md.
module "endpoints" {
  source = "../../../../templates/endpoints"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
