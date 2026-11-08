data "aws_ec2_transit_gateway" "transit_gateway" {
  provider = aws.hub
  count    = local.ours ? 1 : 0

  filter {
    name   = "tag:Component"
    values = ["hub"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ec2_transit_gateway" "parent" {
  count = local.parent ? 1 : 0

  id = local.network.transit_gateway.id

  depends_on = [aws_ram_resource_share_accepter.parent]
}

data "aws_ec2_transit_gateway_route_table" "route_tables" {
  provider = aws.hub
  for_each = local.ours ? toset(["restricted", "standard", "shared"]) : toset([])

  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.transit_gateway[0].id]
  }
  filter {
    name   = "tag:Segment"
    values = [each.key]
  }
}

data "aws_ram_resource_share" "network" {
  provider = aws.hub
  count    = local.cross_account ? 1 : 0

  name           = "network-01"
  resource_owner = "SELF"
}

data "aws_route53_resolver_rule" "hub" {
  for_each = local.peered ? toset([]) : toset(local.network.resolver.domains)

  name      = "dns-01-${replace(each.key, ".", "-")}"
  rule_type = "FORWARD"

  depends_on = [aws_ram_resource_share_accepter.network]
}

data "aws_route53_resolver_rule" "private" {
  count = local.resolves_all ? 1 : 0

  name      = "dns-01-${replace(module.ip_plan.dns.private_domain, ".", "-")}"
  rule_type = "FORWARD"

  depends_on = [aws_ram_resource_share_accepter.network]
}

data "aws_route53_zone" "private" {
  provider = aws.hub
  for_each = module.ip_plan.dns.private_zones

  name         = each.key
  private_zone = true
}

data "aws_vpc" "peers" {
  for_each = { for name, p in local.peerings : name => p if p.by_name && p.known && length(local.problems) == 0 }

  region = each.value.region

  tags = {
    Environment = each.value.peer
    Component   = "network"
  }
}

data "aws_vpc_peering_connection" "requested" {
  for_each = length(local.problems) == 0 ? local.named_peerings : toset([])

  cidr_block  = local.requester_cidrs[each.key]
  peer_vpc_id = module.vpc.vpc_id
  status      = "active"
}
