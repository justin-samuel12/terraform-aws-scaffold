locals {
  config_dir = coalesce(var.config_dir, path.root)
  public     = toset(coalesce(try(yamldecode(file("${local.config_dir}/zones.yml")).public, null), []))
  private    = module.ip_plan.dns.private_zones
}
