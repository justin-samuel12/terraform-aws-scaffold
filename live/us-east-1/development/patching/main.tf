# This stack is templates/patching for its environment and region -- docs/architecture.md.
module "patching" {
  source = "../../../../templates/patching"

  environment = local.environment
}
