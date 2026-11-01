# This stack is templates/keys for its environment and region -- docs/architecture.md.
module "keys" {
  source = "../../../../templates/keys"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
