# This stack is templates/databases for its environment and region -- docs/architecture.md.
module "databases" {
  source = "../../../../templates/databases"

  environment = local.environment
}
