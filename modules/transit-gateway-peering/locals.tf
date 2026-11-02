locals {
  sides = { requester = var.requester, accepter = var.accepter }

  # "<side> <route table name> <cidr>" -> one static route; peering attachments do not propagate. Keyed by name, which is known
  # at plan time, rather than by route table ID, which is not until the tables exist.
  routes = merge([
    for side, config in local.sides : merge([
      for table, r in config.routes : {
        for cidr in r.cidrs : "${side} ${table} ${cidr}" => {
          region         = config.region
          route_table_id = r.route_table_id
          destination    = cidr
        }
      }
    ]...)
  ]...)
}
