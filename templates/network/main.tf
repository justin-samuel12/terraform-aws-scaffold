# One environment's VPC in one region; everything that differs lives in config/ -- docs/network.md.
# What only the hub's owner may do (accept and route the attachment, authorize private zones) goes through aws.hub: the hub's
# account, which is this one in single-account mode.
module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# The region's hub is found by its tags in the hub's account, not by reading the hub stack's state.
data "aws_ec2_transit_gateway" "transit_gateway" {
  provider = aws.hub

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
  provider = aws.hub
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

# Another account: the hub shares its Transit Gateway, resolver rules and prefix lists with this one (network-01). Without
# organization sharing, this account accepts the invitation.
data "aws_ram_resource_share" "network" {
  provider = aws.hub
  count    = local.cross_account ? 1 : 0

  name           = "network-01"
  resource_owner = "SELF"
}

resource "aws_ram_resource_share_accepter" "network" {
  count = local.cross_account && !module.ip_plan.organization_sharing ? 1 : 0

  share_arn = data.aws_ram_resource_share.network[0].arn
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
    security_group_referencing  = local.network.security_group_referencing
    route_here                  = false
    shared                      = local.cross_account
  }
  transit_gateway_accepted = local.cross_account ? aws_ec2_transit_gateway_vpc_attachment_accepter.network[0].id : null

  depends_on = [aws_ram_resource_share_accepter.network]
}

# The hub's owner accepts an attachment from another account, then associates and propagates it, in either mode.
resource "aws_ec2_transit_gateway_vpc_attachment_accepter" "network" {
  provider = aws.hub
  count    = local.cross_account ? 1 : 0

  transit_gateway_attachment_id                   = module.vpc.transit_gateway_attachment_id
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = { Name = "${var.environment}-attachment" }
}

resource "aws_ec2_transit_gateway_route_table_association" "network" {
  provider = aws.hub

  transit_gateway_attachment_id  = module.vpc.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.network]
}

resource "aws_ec2_transit_gateway_route_table_propagation" "network" {
  provider = aws.hub
  for_each = toset(local.network.propagates_to)

  transit_gateway_attachment_id  = module.vpc.transit_gateway_attachment_id
  transit_gateway_route_table_id = data.aws_ec2_transit_gateway_route_table.route_tables[each.key].id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment_accepter.network]
}

# The hub's DNS forwarding rules (Active Directory and other HQ domains), one per domain in config/global.yml, found by name;
# shared to this account when it is another one. Keyed by domain, which is known before the share is accepted.
data "aws_route53_resolver_rule" "hub" {
  for_each = module.ip_plan.dns.forward

  name      = "dns-01-${replace(each.key, ".", "-")}"
  rule_type = "FORWARD"

  depends_on = [aws_ram_resource_share_accepter.network]
}

resource "aws_route53_resolver_rule_association" "hub" {
  for_each = module.ip_plan.dns.forward

  resolver_rule_id = data.aws_route53_resolver_rule.hub[each.key].id
  vpc_id           = module.vpc.vpc_id
}

# The private hosted zones in config/global.yml, in the hub's account; this VPC attaches itself to each. From another account,
# the zone's owner authorizes it first.
data "aws_route53_zone" "private" {
  provider = aws.hub
  for_each = module.ip_plan.dns.private_zones

  name         = each.key
  private_zone = true
}

resource "aws_route53_vpc_association_authorization" "private" {
  provider = aws.hub
  for_each = local.cross_account ? module.ip_plan.dns.private_zones : toset([])

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id
}

resource "aws_route53_zone_association" "private" {
  for_each = module.ip_plan.dns.private_zones

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id

  depends_on = [aws_route53_vpc_association_authorization.private]
}
