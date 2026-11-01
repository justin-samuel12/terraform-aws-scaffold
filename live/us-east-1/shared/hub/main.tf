# This stack is templates/hub for its environment and region -- docs/architecture.md.
module "hub" {
  source = "../../../../templates/hub"

  region      = local.region
  config_path = local.config_dir
}
