locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "

  sides = { requester = var.requester, accepter = var.accepter }

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
