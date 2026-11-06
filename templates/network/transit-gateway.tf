resource "aws_ram_resource_share_accepter" "network" {
  count = local.cross_account && !module.ip_plan.organization_sharing ? 1 : 0

  share_arn = data.aws_ram_resource_share.network[0].arn
}

resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "network" {
  provider = aws.hub
  count    = local.cross_account ? 1 : 0

  transit_gateway_attachment_id                   = module.vpc.transit_gateway_attachment_id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "${title(var.environment)} - Transit Gateway Attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "network" {
  provider = aws.hub
  count    = local.peered ? 0 : 1

  transit_gateway_attachment_id  = module.vpc.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.network]
}

resource "aws_ec2_transit_gateway_route_table_propagation" "network" {
  provider = aws.hub
  for_each = local.peered ? toset([]) : toset(local.network.propagates_to)

  transit_gateway_attachment_id  = module.vpc.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.route_tables[each.key].id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.network]
}
