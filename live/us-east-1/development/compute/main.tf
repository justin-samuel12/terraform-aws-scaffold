# This stack is templates/compute for its environment and region -- docs/architecture.md.
module "compute" {
  source = "../../../../templates/compute"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
