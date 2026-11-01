# This stack is templates/apps for its environment and region -- docs/architecture.md.
module "apps" {
  source = "../../../../templates/apps"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
