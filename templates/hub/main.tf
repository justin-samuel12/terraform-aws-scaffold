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

  # Every segment reaches the internet through the egress VPC.
  routes = {
    for table in local.tables : "${table}-internet" => {
      route_table   = table
      destination   = "0.0.0.0/0"
      attachment_id = module.vpc.transit_gateway_attachment_id
    }
  }
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
    local.dns_tier ? { dns = { cidrs = local.network.subnets.dns, default_route = "none", transit_routes = [module.ip_plan.internal_cidr] } } : {},
  )
  nat_gateway_subnets = "public"

  transit_gateway = {
    id                         = module.transit_gateway.transit_gateway_id
    subnets                    = "transit"
    association_route_table_id = module.transit_gateway.route_table_ids["shared"]
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
