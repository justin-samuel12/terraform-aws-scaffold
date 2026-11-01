# This stack is templates/session-manager for its environment and region -- docs/architecture.md.
module "session_manager" {
  source = "../../../../templates/session-manager"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
