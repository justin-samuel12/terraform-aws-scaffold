# This stack is templates/baseline for its environment and region -- docs/architecture.md.
module "baseline" {
  source = "../../../../templates/baseline"

  region      = local.region
  config_path = local.config_dir
}
