module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "vpc" {
  source = "../../modules/vpc"

  cidr_block            = local.network.cidr
  availability_zone_ids = local.network.zones

  subnets             = local.subnets
  routes              = length(local.problems) == 0 ? local.module_routes : {}
  network_acls        = length(local.problems) == 0 ? local.network_acls : {}
  nat_gateway_subnets = local.uses_nat && length(local.problems) == 0 ? "public" : null

  transit_gateway = local.peered ? null : {
    id                          = data.aws_ec2_transit_gateway.transit_gateway[0].id
    subnets                     = "transit"
    association_route_table_id  = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id
    propagation_route_table_ids = { for table in local.network.propagates_to : table => data.aws_ec2_transit_gateway_route_table.route_tables[table].id }
    security_group_referencing  = local.network.security_group_referencing
    route_here                  = false
    shared                      = local.cross_account
  }
  transit_gateway_accepted = local.cross_account ? aws_ec2_transit_gateway_vpc_attachment_accepter.network[0].id : null

  depends_on = [aws_ram_resource_share_accepter.network]
}
