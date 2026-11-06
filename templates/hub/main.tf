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

module "vpn" {
  source   = "../../modules/vpn"
  for_each = merge({}, [for name, site in module.ip_plan.sites : { for ip in site.ip_addresses : "${name}/${ip}" => { site = name, ip_address = ip, bgp_asn = site.bgp_asn } }]...)

  name                        = each.value.site
  transit_gateway_id          = module.transit_gateway.transit_gateway_id
  customer_gateway            = { ip_address = each.value.ip_address, bgp_asn = each.value.bgp_asn }
  association_route_table_id  = module.transit_gateway.route_table_ids["shared"]
  propagation_route_table_ids = module.transit_gateway.route_table_ids
}

module "prefix_list" {
  source = "../../modules/prefix-list"

  lists = module.ip_plan.prefix_lists
}

module "managed_directory" {
  source = "../../modules/managed-directory"
  count  = local.directory ? 1 : 0

  name        = module.ip_plan.directory.name
  short_name  = module.ip_plan.directory.short_name
  edition     = module.ip_plan.directory.edition
  description = module.ip_plan.directory.description
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = slice(module.vpc.subnet_ids["dns"], 0, 2)
}

module "route53_resolver" {
  source = "../../modules/route53-resolver"
  count  = local.dns_tier ? 1 : 0

  name          = "dns-01"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = slice(module.vpc.subnet_ids["dns"], 0, min(2, length(module.vpc.subnet_ids["dns"])))
  clients_cidrs = concat([module.ip_plan.internal_cidr], [for c in module.ip_plan.site_cidrs : c if !startswith(c, "10.")])
  inbound       = local.network.resolver.inbound
  forward       = local.network.resolver.outbound ? merge(module.ip_plan.dns.forward, local.directory ? { (module.ip_plan.directory.name) = module.managed_directory[0].dns_ip_addresses } : {}) : {}

  inbound_domains = local.network.resolver.inbound && local.network.resolver.outbound && module.ip_plan.dns.private_domain != null && length(module.ip_plan.dns.resolve_all) > 0 ? [module.ip_plan.dns.private_domain] : []
}

module "peering" {
  source   = "../../modules/transit-gateway-peering"
  for_each = toset(local.peer_regions)

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

resource "aws_ram_resource_share" "network" {
  count = length(local.share_accounts) > 0 ? 1 : 0

  name                      = "network-01"
  allow_external_principals = !module.ip_plan.organization_sharing

  tags = { Name = "${local.name_prefix}Network Share" }
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
