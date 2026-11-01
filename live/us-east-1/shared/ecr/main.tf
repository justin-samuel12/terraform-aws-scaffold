# This stack is templates/ecr for its environment and region -- docs/architecture.md.
module "ecr" {
  source = "../../../../templates/ecr"

  region      = local.region
  config_path = local.config_dir
}
