# This stack is templates/access for its environment and region -- docs/architecture.md.
module "access" {
  source = "../../../../templates/access"

  environment = local.environment
}
