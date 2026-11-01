# One environment's VPC in one region; everything that differs lives in modules/ip-plan -- docs/network.md.
module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The region's hub is found by its tags, not by reading the hub stack's state.
data "aws_ec2_transit_gateway" "transit_gateway" {
  filter {
    name   = "tag:Component"
    values = ["hub"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ec2_transit_gateway_route_table" "route_tables" {
  for_each = toset(["restricted", "standard", "shared"])

  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.transit_gateway.id]
  }
  filter {
    name   = "tag:Name"
    values = ["tgw-01-${each.key}"]
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                  = "vpc-01"
  cidr_block            = local.network.cidr
  availability_zone_ids = local.network.zones

  subnets = local.subnets

  transit_gateway = {
    id                          = data.aws_ec2_transit_gateway.transit_gateway.id
    subnets                     = "transit"
    association_route_table_id  = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id
    propagation_route_table_ids = { for table in local.network.propagates_to : table => data.aws_ec2_transit_gateway_route_table.route_tables[table].id }
  }
}

# The hub's DNS forwarding rules (Active Directory and other HQ domains), found by name; this VPC asks HQ for those domains.
data "aws_route53_resolver_rules" "hub" {
  rule_type  = "FORWARD"
  name_regex = "^dns-01-"
}

resource "aws_route53_resolver_rule_association" "hub" {
  for_each = data.aws_route53_resolver_rules.hub.resolver_rule_ids

  resolver_rule_id = each.value
  vpc_id           = module.vpc.vpc_id
}

# The private hosted zones in config/global.yml, found by name; this VPC attaches itself to each.
data "aws_route53_zone" "private" {
  for_each = module.ip_plan.dns.private_zones

  name         = each.key
  private_zone = true
}

resource "aws_route53_zone_association" "private" {
  for_each = module.ip_plan.dns.private_zones

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id
}
