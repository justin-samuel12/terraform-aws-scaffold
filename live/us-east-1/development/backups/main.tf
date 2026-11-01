# This stack is templates/backups for its environment and region -- docs/architecture.md.
module "backups" {
  source = "../../../../templates/backups"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
