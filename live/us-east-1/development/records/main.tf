# This stack is templates/records for its environment and region -- docs/architecture.md.
module "records" {
  source = "../../../../templates/records"

  environment = local.environment
}
