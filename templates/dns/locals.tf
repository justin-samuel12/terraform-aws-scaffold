locals {
  config_dir = coalesce(var.config_dir, path.root)
  public     = toset(coalesce(try(yamldecode(file("${local.config_dir}/zones.yml")).public, null), []))
  private    = module.ip_plan.dns.private_zones

  # Every other region's hub joins the private zones from here, so no hub waits for this stack and the primary hub can still
  # be applied last. Only hubs in the primary hub's account can be associated from it.
  primary_account = module.ip_plan.accounts.hubs[module.ip_plan.primary_region]
  other_hubs      = length(local.private) == 0 ? [] : sort([for region, account in module.ip_plan.accounts.hubs : region if region != module.ip_plan.primary_region])
  foreign_hubs    = [for region in local.other_hubs : region if module.ip_plan.accounts.hubs[region] != local.primary_account]
  associations    = { for pair in setproduct(sort(tolist(local.private)), local.other_hubs) : "${pair[0]} ${pair[1]}" => { zone = pair[0], region = pair[1] } if !contains(local.foreign_hubs, pair[1]) }
}
