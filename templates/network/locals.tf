locals {
  network = module.ip_plan.networks["${var.environment}/${var.region}"]

  # A tier's route in config/<region>.yml, as the vpc module's default route; internal adds only the internal range to the hub.
  default_routes = { hub = "transit", internal = "none", internet = "internet", none = "none" }

  subnets = {
    for tier, cidrs in local.network.subnets : tier => {
      cidrs          = cidrs
      default_route  = local.default_routes[local.network.routes[tier]]
      transit_routes = local.network.routes[tier] == "internal" ? [module.ip_plan.internal_cidr] : []
      reserved_cidrs = try(local.network.reserved[tier], [])
    }
  }
}
