locals {
  sides = { requester = var.requester, accepter = var.accepter }

  # "<side> <route table id> <cidr>" -> one static route; peering attachments do not propagate.
  routes = merge([
    for side, config in local.sides : merge([
      for route_table_id, cidrs in config.routes : {
        for cidr in cidrs : "${side} ${route_table_id} ${cidr}" => {
          region         = config.region
          route_table_id = route_table_id
          destination    = cidr
        }
      }
    ]...)
  ]...)
}
