locals {
  network = module.ip_plan.networks["${var.environment}/${var.region}"]

  # Another account than the hub's: the hub shares the network with this one, and its owner accepts and routes the attachment.
  hub_account   = try(module.ip_plan.networks["shared/${var.region}"].account_id, "")
  cross_account = local.network.account_id != "" && local.hub_account != "" && local.network.account_id != local.hub_account

  # A tier's route in config/<region>.yml, as the vpc module's default route; internal adds only the internal range to the hub.
  default_routes = { hub = "transit", internal = "none", internet = "internet", none = "none" }

  # Everything private the hub routes: 10.0.0.0/8, and HQ's ranges outside it (an office on 192.168.0.0/16, say).
  private_ranges = concat([module.ip_plan.internal_cidr], [for c in module.ip_plan.hq.cidrs : c if !startswith(c, "10.")])

  subnets = {
    for tier, cidrs in local.network.subnets : tier => {
      cidrs          = cidrs
      default_route  = local.default_routes[local.network.routes[tier]]
      transit_routes = local.network.routes[tier] == "internal" ? local.private_ranges : []
      reserved_cidrs = try(local.network.reserved[tier], [])
    }
  }
}
