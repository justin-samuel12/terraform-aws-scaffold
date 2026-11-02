# One region's hub: Transit Gateway, egress VPC and the VPN to HQ -- docs/network.md.
module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "transit_gateway" {
  source = "../../modules/transit-gateway"

  name            = "tgw-01"
  amazon_side_asn = local.network.amazon_side_asn
  route_tables    = local.tables

  security_group_referencing = local.network.security_group_referencing

  # Every segment reaches the internet through the egress VPC. Restricted and standard also blackhole the rest of 10.0.0.0/8:
  # otherwise traffic to another segment would follow 0.0.0.0/0 to the egress VPC and come back through the shared table.
  # The routes each table should have (its own segment, shared, HQ, the peering) are more specific and still win.
  routes = merge(
    {
      for table in local.tables : "${table}-internet" => {
        route_table   = table
        destination   = "0.0.0.0/0"
        attachment_id = module.vpc.transit_gateway_attachment_id
      }
    },
    {
      for table in ["restricted", "standard"] : "${table}-isolated" => {
        route_table = table
        destination = module.ip_plan.internal_cidr
        blackhole   = true
      }
    },
  )
}

module "vpc" {
  source = "../../modules/vpc"

  name                  = "vpc-01"
  cidr_block            = local.network.cidr
  availability_zone_ids = local.network.zones

  subnets = merge(
    {
      public  = { cidrs = local.network.subnets.public, default_route = "internet", transit_routes = [module.ip_plan.internal_cidr] }
      transit = { cidrs = local.network.subnets.transit, default_route = "nat" }
    },
    local.dns_tier ? { dns = { cidrs = local.network.subnets.dns, default_route = "none", transit_routes = local.private_ranges } } : {},
  )
  nat_gateway_subnets = "public"

  transit_gateway = {
    id                         = module.transit_gateway.transit_gateway_id
    subnets                    = "transit"
    association_route_table_id = module.transit_gateway.route_table_ids["shared"]
    security_group_referencing = local.network.security_group_referencing
  }
}

# Built only once HQ's public IP is set in modules/ip-plan.
module "vpn" {
  source = "../../modules/vpn"
  count  = module.ip_plan.hq.ip_address == null ? 0 : 1

  name                        = "vpn-01"
  transit_gateway_id          = module.transit_gateway.transit_gateway_id
  customer_gateway            = { ip_address = module.ip_plan.hq.ip_address, bgp_asn = module.ip_plan.hq.bgp_asn }
  association_route_table_id  = module.transit_gateway.route_table_ids["shared"]
  propagation_route_table_ids = module.transit_gateway.route_table_ids
}

# Named address groups for security group rules, from config/global.yml.
module "prefix_list" {
  source = "../../modules/prefix-list"

  lists = module.ip_plan.prefix_lists
}

# DNS between AWS and HQ: the endpoints live here; each environment's network associates the rules with its VPC.
module "route53_resolver" {
  source = "../../modules/route53-resolver"
  count  = local.dns_tier ? 1 : 0

  name          = "dns-01"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.subnet_ids["dns"]
  clients_cidrs = concat([module.ip_plan.internal_cidr], module.ip_plan.hq.cidrs)
  inbound       = module.ip_plan.dns.inbound
  forward       = module.ip_plan.dns.forward
}

# The primary hub's VPC is the one each private zone was created with; the other hubs attach themselves.
data "aws_route53_zone" "private" {
  for_each = local.network.primary ? toset([]) : module.ip_plan.dns.private_zones

  name         = each.key
  private_zone = true
}

resource "aws_route53_zone_association" "private" {
  for_each = local.network.primary ? toset([]) : module.ip_plan.dns.private_zones

  zone_id = data.aws_route53_zone.private[each.key].zone_id
  vpc_id  = module.vpc.vpc_id
}

# The other regions' hubs, found by their tags; each must be applied before the primary hub requests its peering.
data "aws_ec2_transit_gateway" "peers" {
  for_each = toset(local.peer_regions)

  region = each.key

  filter {
    name   = "tag:Component"
    values = ["hub"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ec2_transit_gateway_route_table" "peers" {
  for_each = { for pair in setproduct(local.peer_regions, local.tables) : "${pair[0]}/${pair[1]}" => { region = pair[0], table = pair[1] } }

  region = each.value.region

  filter {
    name   = "transit-gateway-id"
    values = [data.aws_ec2_transit_gateway.peers[each.value.region].id]
  }
  filter {
    name   = "tag:Name"
    values = ["tgw-01-${each.value.table}"]
  }
}

module "peering" {
  source   = "../../modules/transit-gateway-peering"
  for_each = toset(local.peer_regions)

  name = format("tgw-peering-%02d", index(local.peer_regions, each.key) + 1)

  requester = {
    region             = var.region
    transit_gateway_id = module.transit_gateway.transit_gateway_id
    route_table_id     = module.transit_gateway.route_table_ids["shared"]
    routes             = { for table in local.tables : table => { route_table_id = module.transit_gateway.route_table_ids[table], cidrs = flatten([for segment in local.reach[table] : local.cidrs[each.key][segment]]) } }
  }

  accepter = {
    region             = each.key
    transit_gateway_id = data.aws_ec2_transit_gateway.peers[each.key].id
    route_table_id     = data.aws_ec2_transit_gateway_route_table.peers["${each.key}/shared"].id
    routes             = { for table in local.tables : table => { route_table_id = data.aws_ec2_transit_gateway_route_table.peers["${each.key}/${table}"].id, cidrs = flatten([for segment in local.reach[table] : local.cidrs[var.region][segment]]) } }
  }
}

# Multiple accounts: the network is shared with every other account that has an environment here (one share, network-01).
# Within an AWS Organization with RAM sharing on, it reaches them directly; otherwise each accepts it from its network stack.
resource "aws_ram_resource_share" "network" {
  count = length(local.share_accounts) > 0 ? 1 : 0

  name                      = "network-01"
  allow_external_principals = !module.ip_plan.organization_sharing

  tags = { Name = "network-01" }
}

resource "aws_ram_resource_association" "network" {
  for_each = length(local.share_accounts) > 0 ? local.share_resources : {}

  resource_share_arn = aws_ram_resource_share.network[0].arn
  resource_arn       = each.value
}

resource "aws_ram_principal_association" "network" {
  for_each = toset(local.share_accounts)

  resource_share_arn = aws_ram_resource_share.network[0].arn
  principal          = each.key
}

