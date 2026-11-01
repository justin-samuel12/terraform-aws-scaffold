# This stack is templates/buckets for its environment and region -- docs/architecture.md.
module "buckets" {
  source = "../../../../templates/buckets"

  environment = local.environment
  region      = local.region
}
