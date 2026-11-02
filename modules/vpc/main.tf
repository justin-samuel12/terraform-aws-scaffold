resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }

  # Replacing a VPC or a subnet takes down everything in it; a plan that would do so fails here, and removal is a reviewed code change.
  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(setsubtract(var.availability_zone_ids, data.aws_availability_zones.available.zone_ids)) == 0
      error_message = "These zone IDs are not available in this region: ${join(", ", setsubtract(var.availability_zone_ids, data.aws_availability_zones.available.zone_ids))}."
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "subnets" {
  for_each = local.subnets

  vpc_id               = aws_vpc.vpc.id
  cidr_block           = each.value.cidr
  availability_zone_id = each.value.zone

  # Subnet names one subnet the same way in every environment, so an instance can be placed by it -- docs/network.md.
  tags = { Name = "${var.name}-${each.value.tier}-${each.value.zone}", Tier = each.value.tier, Subnet = "${each.value.tier}-${split("-", each.value.zone)[1]}" }

  lifecycle {
    prevent_destroy = true
  }
}

# AWS never hands out an address in this block on its own; only addresses asked for by name come from it.
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
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_eip" "eips" {
  for_each = local.nat_gateways

  domain = "vpc"
  tags   = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "nat_gateways" {
  for_each = local.nat_gateways

  allocation_id = aws_eip.eips[each.key].id
  subnet_id     = aws_subnet.subnets["${var.nat_gateway_subnets}-${each.key}"].id
  tags          = { Name = "${var.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.internet_gateway]
}

resource "aws_route_table" "route_tables" {
  for_each = local.subnets

  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.name}-${each.value.tier}-${each.value.zone}", Tier = each.value.tier }
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

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment]
}

resource "aws_route" "transit_routes" {
  for_each = local.transit_routes

  route_table_id         = aws_route_table.route_tables[each.value.subnet].id
  destination_cidr_block = each.value.destination
  transit_gateway_id     = var.transit_gateway.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment]
}

resource "aws_ec2_transit_gateway_vpc_attachment" "transit_gateway_vpc_attachment" {
  count = var.transit_gateway == null ? 0 : 1

  transit_gateway_id                              = var.transit_gateway.id
  vpc_id                                          = aws_vpc.vpc.id
  subnet_ids                                      = [for zone in var.availability_zone_ids : aws_subnet.subnets["${var.transit_gateway.subnets}-${zone}"].id]
  appliance_mode_support                          = var.transit_gateway.appliance_mode ? "enable" : "disable"
  security_group_referencing_support              = var.transit_gateway.security_group_referencing ? "enable" : "disable"
  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "${var.name}-attachment" }
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

# Every VPC's traffic is recorded, accepted and rejected alike, for incident response and audit -- docs/network.md.
resource "aws_flow_log" "flow_log" {
  vpc_id               = aws_vpc.vpc.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  iam_role_arn         = aws_iam_role.flow_log.arn

  tags = { Name = "${var.name}-flow-log" }

  # Delivery starts at once; without the policy the first logs are lost.
  depends_on = [aws_iam_role_policy.flow_log]
}

# Named by VPC ID: every environment's VPC is vpc-01, and they may share an account.
resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/vpc/flow-logs/${aws_vpc.vpc.id}"
  retention_in_days = var.flow_log_retention_days

  tags = { Name = "${var.name}-flow-log" }
}

resource "aws_iam_role" "flow_log" {
  name               = "flow-logs-${aws_vpc.vpc.id}"
  assume_role_policy = local.flow_log_assume_policy

  tags = { Name = "${var.name}-flow-log" }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_log.id
  policy = local.flow_log_write_policy
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# AWS does not allow deleting a VPC's default security group; with no rules it admits and sends nothing.
resource "aws_default_security_group" "default" {
  vpc_id  = aws_vpc.vpc.id
  ingress = []
  egress  = []

  tags = { Name = "${var.name}-default-unused" }
}
