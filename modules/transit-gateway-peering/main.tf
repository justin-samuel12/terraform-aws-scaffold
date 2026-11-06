resource "aws_ec2_transit_gateway_peering_attachment" "peering_attachment" {
  region                  = var.requester.region
  transit_gateway_id      = var.requester.transit_gateway_id
  peer_transit_gateway_id = var.accepter.transit_gateway_id
  peer_region             = var.accepter.region

  tags = { Name = "${local.name_prefix}Transit Gateway Peering to ${var.accepter.region}" }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "peering_attachment_accepter" {
  region                        = var.accepter.region
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.peering_attachment.id

  tags = { Name = "${local.name_prefix}Transit Gateway Peering from ${var.requester.region}" }
}

resource "aws_ec2_transit_gateway_route_table_association" "route_table_associations" {
  for_each = local.sides

  region                         = each.value.region
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.peering_attachment_accepter.transit_gateway_attachment_id
  transit_gateway_route_table_id = each.value.route_table_id
}

resource "aws_ec2_transit_gateway_route" "routes" {
  for_each = local.routes

  region                         = each.value.region
  transit_gateway_route_table_id = each.value.route_table_id
  destination_cidr_block         = each.value.destination
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.peering_attachment_accepter.transit_gateway_attachment_id

  depends_on = [aws_ec2_transit_gateway_route_table_association.route_table_associations]
}
