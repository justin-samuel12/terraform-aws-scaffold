# This stack is templates/dns for its environment and region -- docs/architecture.md.
module "dns" {
  source      = "../../../../templates/dns"
  config_path = local.config_dir
}
