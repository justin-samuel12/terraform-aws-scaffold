# This stack is templates/waf for its environment and region -- docs/architecture.md.
module "waf" {
  source = "../../../../templates/waf"

  region = local.region
}
