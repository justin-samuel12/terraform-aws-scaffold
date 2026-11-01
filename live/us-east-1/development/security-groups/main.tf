# This stack is templates/security-groups for its environment and region -- docs/architecture.md.
module "security_groups" {
  source = "../../../../templates/security-groups"

  environment = local.environment
  region      = local.region
  config_path = local.config_dir
}
