locals {
  network = module.ip_plan.networks["${var.environment}/${var.region}"]
  peered  = local.network.connectivity == "peering"
  parent  = !local.peered && local.network.transit_gateway.owner == "parent"
  ours    = !local.peered && !local.parent

  transit_gateway_id = local.peered ? null : (local.parent ? data.aws_ec2_transit_gateway.parent[0].id : data.aws_ec2_transit_gateway.transit_gateway[0].id)

  hub_account   = try(module.ip_plan.networks["shared/${var.region}"].account_id, "")
  cross_account = !local.peered && local.network.account_id != "" && local.hub_account != "" && local.network.account_id != local.hub_account

  default_routes = { hub = "transit", internal = "none", internet = "internet", none = "none" }

  private_ranges = concat([module.ip_plan.internal_cidr], [for c in module.ip_plan.site_cidrs : c if !startswith(c, "10.")])

  subnets = {
    for tier, cidrs in local.network.subnets : tier => {
      cidrs          = cidrs
      default_route  = local.peered ? "none" : local.default_routes[local.network.routes[tier]]
      transit_routes = !local.peered && local.network.routes[tier] == "internal" ? local.private_ranges : []
      reserved_cidrs = try(local.network.reserved[tier], [])
    }
  }

  resolves_all = !local.peered && contains(module.ip_plan.dns.resolve_all, var.environment)

  config_dir = coalesce(var.config_dir, "${path.root}/config")
  kinds      = ["route-table", "peering", "network-acl"]
  paths      = fileset(local.config_dir, "**/*.yml")
  found = {
    for kind in local.kinds : kind => {
      for path in local.paths : trimsuffix(basename(path), ".yml") => path... if split("/", path)[0] == kind
    }
  }
  files = { for kind, names in local.found : kind => { for name, paths in names : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) } }

  tiers      = keys(local.network.subnets)
  route_keys = ["destination_cidr_block", "gateway_id", "nat_gateway_id", "vpc_peering_connection_id", "transit_gateway_id"]
  targets    = ["gateway_id", "nat_gateway_id", "vpc_peering_connection_id", "transit_gateway_id"]
  rule_keys  = ["rule_no", "action", "protocol", "cidr_block", "from_port", "to_port", "icmp_type", "icmp_code"]

  routes = flatten([
    for tier, f in local.files["route-table"] : [
      for r in try(tolist(f.route), []) : {
        tier                      = tier
        destination_cidr_block    = try(tostring(r.destination_cidr_block), "")
        gateway_id                = try(tostring(r.gateway_id), null)
        nat_gateway_id            = try(tostring(r.nat_gateway_id), null)
        vpc_peering_connection_id = try(tostring(r.vpc_peering_connection_id), null)
        transit_gateway_id        = try(tostring(r.transit_gateway_id), null)
      }
    ]
  ])
  derived_destinations = {
    for tier, s in local.subnets : tier => concat(s.default_route == "none" ? [] : ["0.0.0.0/0"], s.transit_routes)
  }

  peerings = {
    for name, f in local.files.peering : name => {
      peer        = try(tostring(f.peer_vpc_id), "")
      region      = try(tostring(f.peer_region), var.region)
      tags        = try(tomap(f.tags), {})
      by_name     = !startswith(try(tostring(f.peer_vpc_id), ""), "vpc-")
      account     = try(module.ip_plan.networks["${tostring(f.peer_vpc_id)}/${try(tostring(f.peer_region), var.region)}"].account_id, "")
      known       = contains(keys(module.ip_plan.networks), "${try(tostring(f.peer_vpc_id), "")}/${try(tostring(f.peer_region), var.region)}")
      same_region = try(tostring(f.peer_region), var.region) == var.region
    }
  }

  named_peerings = toset([
    for r in local.routes : r.vpc_peering_connection_id
    if r.vpc_peering_connection_id != null && !startswith(coalesce(r.vpc_peering_connection_id, "-"), "pcx-") && !contains(keys(local.peerings), coalesce(r.vpc_peering_connection_id, "-"))
  ])
  requester_cidrs = {
    for name in local.named_peerings : name => coalesce(
      try(module.ip_plan.networks["${name}/${var.region}"].cidr, null),
      try(one([for key, n in module.ip_plan.networks : n.cidr if split("/", key)[0] == name]), null),
      "-",
    )
  }

  module_routes = {
    for r in local.routes : "${r.tier} ${r.destination_cidr_block}" => {
      tier                   = r.tier
      destination_cidr_block = r.destination_cidr_block
      gateway_id             = r.gateway_id
      nat_gateway_id         = r.nat_gateway_id
      vpc_peering_connection_id = r.vpc_peering_connection_id == null ? null : (
        startswith(r.vpc_peering_connection_id, "pcx-") ? r.vpc_peering_connection_id :
        contains(keys(local.peerings), r.vpc_peering_connection_id) ? aws_vpc_peering_connection.peerings[r.vpc_peering_connection_id].id :
        try(data.aws_vpc_peering_connection.requested[r.vpc_peering_connection_id].id, null)
      )
      transit_gateway_id = r.transit_gateway_id == null ? null : r.transit_gateway_id == "hub" ? local.transit_gateway_id : r.transit_gateway_id
    }
  }

  network_acls = {
    for tier, f in local.files["network-acl"] : tier => {
      for direction in ["ingress", "egress"] : direction => [
        for r in try(tolist(f[direction]), []) : {
          rule_no    = try(tonumber(r.rule_no), 0)
          action     = try(tostring(r.action), "")
          protocol   = try(tostring(r.protocol), "")
          cidr_block = try(tostring(r.cidr_block), "")
          from_port  = try(tonumber(r.from_port), 0)
          to_port    = try(tonumber(r.to_port), 0)
          icmp_type  = try(tonumber(r.icmp_type), null)
          icmp_code  = try(tonumber(r.icmp_code), null)
        }
      ]
    }
  }

  uses_nat = anytrue([for r in local.routes : r.nat_gateway_id != null])

  problems = concat(
    [for path in local.paths : "config/${path}: files go in config/route-table/<tier>.yml, config/peering/<name>.yml or config/network-acl/<tier>.yml" if length(split("/", path)) != 2 || !contains(local.kinds, split("/", path)[0])],
    flatten([for kind, names in local.found : [for name, paths in names : "${kind}/${name}.yml is in more than one place (${join(", ", sort(paths))})" if length(paths) > 1]]),
    [for tier, f in local.files["route-table"] : "route-table/${tier}.yml: ${tier} is not a tier of this VPC (${join(", ", local.tiers)})" if !contains(local.tiers, tier)],
    [for tier, f in local.files["route-table"] : "route-table/${tier}.yml: its one key is route, a list of aws_route arguments" if !can(keys(f)) || try(keys(f), []) != ["route"] || !can(tolist(f.route))],
    flatten([for tier, f in local.files["route-table"] : [
      for r in try(tolist(f.route), []) : "route-table/${tier}.yml: a route takes ${join(", ", local.route_keys)}, with destination_cidr_block and exactly one target"
      if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.route_keys, k)]) || !can(cidrnetmask(r.destination_cidr_block)) || length([for t in local.targets : t if can(r[t])]) != 1
    ]]),
    [for r in local.routes : "route-table/${r.tier}.yml: gateway_id is own, this VPC's internet gateway" if r.gateway_id != null && r.gateway_id != "own"],
    [for r in local.routes : "route-table/${r.tier}.yml: nat_gateway_id is own, the NAT gateway in the subnet's zone" if r.nat_gateway_id != null && r.nat_gateway_id != "own"],
    [for r in local.routes : "route-table/${r.tier}.yml: nat_gateway_id own is for a VPC with connectivity: peering; one on the hub goes out through the hub" if r.nat_gateway_id != null && !local.peered],
    [for r in local.routes : "route-table/${r.tier}.yml: transit_gateway_id is for a VPC on the hub; this one has connectivity: peering" if r.transit_gateway_id != null && local.peered],
    [for r in local.routes : "route-table/${r.tier}.yml: transit_gateway_id is hub, this region's hub, or a Transit Gateway id (tgw- and 17 hex digits)" if r.transit_gateway_id != null && r.transit_gateway_id != "hub" && !can(regex("^tgw-[0-9a-f]{8,17}$", coalesce(r.transit_gateway_id, "-")))],
    [for r in local.routes : "route-table/${r.tier}.yml: ${r.destination_cidr_block} is already routed for the ${r.tier} tier by config/global.yml" if contains(try(local.derived_destinations[r.tier], []), r.destination_cidr_block)],
    [for key in distinct([for r in local.routes : "${r.tier} ${r.destination_cidr_block}"]) : "route-table/${split(" ", key)[0]}.yml: ${split(" ", key)[1]} is routed twice" if length([for r in local.routes : r if "${r.tier} ${r.destination_cidr_block}" == key]) > 1],
    [for x in [1] : "route-table: nat_gateway_id own needs a public tier (public: true in config/${var.region}.yml)" if local.uses_nat && !contains(local.tiers, "public")],
    [for x in [1] : "route-table: nat_gateway_id own needs route-table/public.yml to send 0.0.0.0/0 to gateway_id own, so the NAT gateways reach the internet" if local.uses_nat && contains(local.tiers, "public") && !anytrue([for r in local.routes : r.tier == "public" && r.destination_cidr_block == "0.0.0.0/0" && r.gateway_id == "own"])],
    [for name in local.named_peerings : "vpc_peering_connection_id ${name}: not a file in config/peering/, a pcx- id, or an environment in config/ that peers with this one" if local.requester_cidrs[name] == "-"],
    [for name, f in local.files.peering : "peering/${name}.yml: keys are peer_vpc_id, peer_region and tags, as aws_vpc_peering_connection takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(["peer_vpc_id", "peer_region", "tags"], k)]) || !can(tostring(f.peer_vpc_id))],
    [for name, p in local.peerings : "peering/${name}.yml: peer_vpc_id ${p.peer} is not a network in config/${p.region}.yml (an environment's name, or a vpc- id)" if p.by_name && !p.known],
    [for name, p in local.peerings : "peering/${name}.yml: ${p.peer} is ${var.environment} itself" if p.by_name && p.peer == var.environment && p.same_region],
    [for name, p in local.peerings : "peering/${name}.yml: ${p.peer} is in another account; peering across accounts needs that account to accept, which is not built yet" if p.by_name && p.known && p.account != local.network.account_id],
    [for tier, f in local.files["network-acl"] : "network-acl/${tier}.yml: ${tier} is not a tier of this VPC (${join(", ", local.tiers)})" if !contains(local.tiers, tier)],
    [for tier, f in local.files["network-acl"] : "network-acl/${tier}.yml: keys are ingress and egress, lists of aws_network_acl rules" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(["ingress", "egress"], k)])],
    flatten([for tier, f in local.files["network-acl"] : [
      for d in ["ingress", "egress"] : [
        for r in try(tolist(f[d]), []) : "network-acl/${tier}.yml: a rule in ${d} takes ${join(", ", local.rule_keys)}; rule_no, action, protocol and cidr_block are required"
        if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || !alltrue([for k in ["rule_no", "action", "protocol", "cidr_block"] : can(r[k])])
      ]
    ]]),
  )
}
