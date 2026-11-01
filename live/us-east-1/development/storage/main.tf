# This stack is templates/storage for its environment and region -- docs/architecture.md.
module "storage" {
  source = "../../../../templates/storage"

  environment = local.environment
}
