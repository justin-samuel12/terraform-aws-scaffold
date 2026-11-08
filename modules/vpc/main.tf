resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}VPC" }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(setsubtract(var.availability_zone_ids, data.aws_availability_zones.available.zone_ids)) == 0
      error_message = "These zone IDs are not available in this region: ${join(", ", setsubtract(var.availability_zone_ids, data.aws_availability_zones.available.zone_ids))}."
    }
  }
}

resource "aws_subnet" "subnets" {
  for_each = local.subnets

  vpc_id               = aws_vpc.vpc.id
  cidr_block           = each.value.cidr
  availability_zone_id = each.value.zone

  tags = { Name = "${local.name_prefix}${local.tier_titles[each.value.tier]} Subnet ${upper(split("-", each.value.zone)[1])}", Tier = each.value.tier, Subnet = "${each.value.tier}-${split("-", each.value.zone)[1]}" }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ec2_subnet_cidr_reservation" "chosen_addresses" {
  for_each = { for key, subnet in local.subnets : key => subnet if subnet.reserved != null }

  subnet_id        = aws_subnet.subnets[each.key].id
  cidr_block       = each.value.reserved
  reservation_type = "explicit"
  description      = "Addresses people choose (${each.value.tier}-${split("-", each.value.zone)[1]})"
}

resource "aws_internet_gateway" "internet_gateway" {
  count = local.internet_gateway ? 1 : 0

  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${local.name_prefix}Internet Gateway" }
}

resource "aws_eip" "eips" {
  for_each = local.nat_gateways

  domain = "vpc"
  tags   = { Name = "${local.name_prefix}NAT Gateway ${upper(split("-", each.key)[1])} Address" }
}

resource "aws_nat_gateway" "nat_gateways" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.eips[each.key].id
  subnet_id     = aws_subnet.subnets["${var.nat_gateway_subnets}-${each.key}"].id
  tags          = { Name = "${local.name_prefix}NAT Gateway ${upper(split("-", each.key)[1])}" }

  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_route_table" "route_tables" {
  for_each = local.subnets

  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${local.name_prefix}${local.tier_titles[each.value.tier]} Route Table ${upper(split("-", each.value.zone)[1])}", Tier = each.value.tier, Subnet = "${each.value.tier}-${split("-", each.value.zone)[1]}" }
}

resource "aws_route_table_association" "route_table_associations" {
  for_each = local.subnets

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.route_tables[each.key].id
}

resource "aws_route" "default_routes" {
  for_each = { for key, subnet in local.subnets : key => subnet if subnet.default_route != "none" }

  route_table_id         = aws_route_table.route_tables[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = each.value.default_route == "internet" ? aws_internet_gateway.internet_gateway[0].id : null
  nat_gateway_id         = each.value.default_route == "nat" ? aws_nat_gateway.nat_gateways[each.value.zone].id : null
  transit_gateway_id     = each.value.default_route == "transit" ? var.transit_gateway.id : null

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment, terraform_data.transit_gateway_accepted]
}

resource "aws_route" "routes" {
  for_each = local.routes

  route_table_id            = aws_route_table.route_tables[each.value.subnet].id
  destination_cidr_block    = each.value.destination_cidr_block
  gateway_id                = each.value.gateway_id == "own" ? aws_internet_gateway.internet_gateway[0].id : null
  nat_gateway_id            = each.value.nat_gateway_id == "own" ? aws_nat_gateway.nat_gateways[each.value.zone].id : null
  vpc_peering_connection_id = each.value.vpc_peering_connection_id
  transit_gateway_id        = each.value.transit_gateway_id
}

resource "aws_network_acl" "network_acls" {
  for_each = var.network_acls

  vpc_id     = aws_vpc.vpc.id
  subnet_ids = [for zone in var.availability_zone_ids : aws_subnet.subnets["${each.key}-${zone}"].id]

  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      rule_no    = ingress.value.rule_no
      action     = ingress.value.action
      protocol   = ingress.value.protocol
      cidr_block = ingress.value.cidr_block
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
      icmp_type  = ingress.value.icmp_type
      icmp_code  = ingress.value.icmp_code
    }
  }

  dynamic "egress" {
    for_each = each.value.egress
    content {
      rule_no    = egress.value.rule_no
      action     = egress.value.action
      protocol   = egress.value.protocol
      cidr_block = egress.value.cidr_block
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
      icmp_type  = egress.value.icmp_type
      icmp_code  = egress.value.icmp_code
    }
  }

  tags = { Name = "${local.name_prefix}${local.tier_titles[each.key]} Network ACL", Tier = each.key }
}

resource "aws_route" "transit_routes" {
  for_each = local.transit_routes

  route_table_id         = aws_route_table.route_tables[each.value.subnet].id
  destination_cidr_block = each.value.destination
  transit_gateway_id     = var.transit_gateway.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment, terraform_data.transit_gateway_accepted]
}

resource "terraform_data" "transit_gateway_accepted" {
  count = var.transit_gateway == null ? 0 : 1

  input = var.transit_gateway_accepted
}

resource "aws_ec2_transit_gateway_vpc_attachment" "transit_gateway_vpc_attachment" {
  count = var.transit_gateway == null ? 0 : 1

  transit_gateway_id                              = var.transit_gateway.id
  vpc_id                                          = aws_vpc.vpc.id
  subnet_ids                                      = [for zone in var.availability_zone_ids : aws_subnet.subnets["${var.transit_gateway.subnets}-${zone}"].id]
  appliance_mode_support                          = var.transit_gateway.appliance_mode ? "enable" : "disable"
  security_group_referencing_support              = var.transit_gateway.security_group_referencing ? "enable" : "disable"
  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = var.transit_gateway.shared ? null : false
  transit_gateway_default_route_table_propagation = var.transit_gateway.shared ? null : false

  tags = { Name = "${local.name_prefix}Transit Gateway Attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "route_table_association" {
  count = var.transit_gateway == null ? 0 : (var.transit_gateway.route_here ? 1 : 0)

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment[0].id
  transit_gateway_route_table_id = var.transit_gateway.association_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "route_table_propagations" {
  for_each = var.transit_gateway == null ? {} : (var.transit_gateway.route_here ? var.transit_gateway.propagation_route_table_ids : {})

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment[0].id
  transit_gateway_route_table_id = each.value
}

resource "aws_flow_log" "flow_log" {
  vpc_id               = aws_vpc.vpc.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn

  tags = { Name = "${local.name_prefix}Flow Logs" }

  depends_on = [aws_iam_role_policy.flow_log]
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/vpc/flow-logs/${aws_vpc.vpc.id}"
  retention_in_days = var.flow_log_retention_days

  tags = { Name = "${local.name_prefix}Flow Logs" }
}

resource "aws_iam_role" "flow_log" {
  name                 = "flow-logs-${aws_vpc.vpc.id}"
  path                 = try(var.role_boundary.path, "/")
  permissions_boundary = try(var.role_boundary.permissions_boundary, null)
  assume_role_policy   = local.flow_log_assume_policy

  tags = { Name = "${local.name_prefix}Flow Logs" }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_log.id
  policy = local.flow_log_write_policy
}

resource "aws_default_security_group" "default" {
  vpc_id  = aws_vpc.vpc.id
  ingress = []
  egress  = []

  tags = { Name = "${local.name_prefix}Default Security Group (unused)" }
}
