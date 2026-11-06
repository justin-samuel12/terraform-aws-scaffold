locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  public  = toset(module.ip_plan.dns.public_domains)
  private = module.ip_plan.dns.private_zones

  primary_account = module.ip_plan.accounts.hubs[module.ip_plan.primary_region]
  other_hubs      = length(local.private) == 0 ? [] : sort([for region, account in module.ip_plan.accounts.hubs : region if region != module.ip_plan.primary_region])
  foreign_hubs    = [for region in local.other_hubs : region if module.ip_plan.accounts.hubs[region] != local.primary_account]
  associations    = { for pair in setproduct(sort(tolist(local.private)), local.other_hubs) : "${pair[0]} ${pair[1]}" => { zone = pair[0], region = pair[1] } if !contains(local.foreign_hubs, pair[1]) }

  domains      = module.ip_plan.dns.public_domains
  dns_account  = local.primary_account
  env_accounts = module.ip_plan.accounts.environments
  writers = {
    for env, z in module.ip_plan.zones : env => {
      account = local.env_accounts[env]
      names   = flatten([for d in local.domains : [d, "*.${d}"]])
    }
    if length(local.domains) > 0 && can(regex("^[0-9]{12}$", try(local.env_accounts[env], ""))) && can(regex("^[0-9]{12}$", try(local.dns_account, ""))) && try(local.env_accounts[env], "") != try(local.dns_account, "")
  }
}

