# This stack is templates/logging for its environment and region -- docs/architecture.md.
module "logging" {
  source = "../../../../templates/logging"

  region = local.region
}
