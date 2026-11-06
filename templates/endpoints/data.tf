data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = local.subnets

  vpc_id = data.aws_vpc.vpc.id
  tags   = { Subnet = each.key }
}

data "aws_route_table" "route_tables" {
  for_each = local.route_tables

  subnet_id = data.aws_subnet.subnets[each.key].id
}

data "aws_security_group" "groups" {
  for_each = local.groups

  vpc_id = data.aws_vpc.vpc.id
  tags   = { Key = each.key }
}
