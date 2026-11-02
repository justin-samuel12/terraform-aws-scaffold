# Default association and propagation are off: every attachment says where it belongs -- docs/network.md.
resource "aws_ec2_transit_gateway" "transit_gateway" {
  description                     = var.name
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  security_group_referencing_support = var.security_group_referencing ? "enable" : "disable"

  tags = { Name = var.name }

  # Every environment routes through the hub; a plan that would replace it fails here.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ec2_transit_gateway_route_table" "route_tables" {
  for_each = var.route_tables

  transit_gateway_id = aws_ec2_transit_gateway.transit_gateway.id
  tags               = { Name = "${var.name}-${each.key}" }
}

resource "aws_ec2_transit_gateway_route" "routes" {
  for_each = var.routes

  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.route_tables[each.value.route_table].id
  destination_cidr_block         = each.value.destination
  transit_gateway_attachment_id  = each.value.attachment_id
  blackhole                      = each.value.blackhole
}
