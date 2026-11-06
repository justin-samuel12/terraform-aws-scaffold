locals {
  names       = try(module.ip_plan.zones[var.environment], { private = null, public = null })
  hub_regions = sort(keys(module.ip_plan.accounts.hubs))
  own_account = try(module.ip_plan.accounts.environments[var.environment], "")
  hub_cross = {
    for r in local.hub_regions : r => can(regex("^[0-9]{12}$", local.own_account)) && can(regex("^[0-9]{12}$", module.ip_plan.accounts.hubs[r])) && local.own_account != module.ip_plan.accounts.hubs[r]
  }
  regions = sort([for key, n in module.ip_plan.networks : split("/", key)[1] if split("/", key)[0] == var.environment])
}
