locals {
  config_dir   = startswith(var.config_path, "/") ? var.config_path : "${path.module}/${var.config_path}"
  region_names = [for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") if name != "global.yml"]
  global       = try(yamldecode(file("${local.config_dir}/global.yml")), {})
  region_files = { for region in local.region_names : region => try(yamldecode(file("${local.config_dir}/${region}.yml")), null) }

  vpc_definitions = merge(
    { for region, d in local.region_files : "shared/${region}" => try(d.hub, null) },
    merge([for region, d in local.region_files : { for environment, n in try(d.vpcs, {}) : "${environment}/${region}" => n if environment != "shared" }]...),
  )
  purposes = { for key in keys(local.vpc_definitions) : key => split("/", key)[0] == "shared" ? "egress" : "spoke" }
  labels = {
    for key in keys(local.vpc_definitions) :
    key => local.purposes[key] == "egress" ? "hub in config/${split("/", key)[1]}.yml" : "vpcs.${split("/", key)[0]} in config/${split("/", key)[1]}.yml"
  }

  segments = ["restricted", "standard", "shared"]
  allowed_keys = {
    file   = ["zones", "hub", "vpcs"]
    egress = ["account_id", "team", "cidr", "amazon_side_asn", "primary", "security_group_referencing"]
    spoke  = ["account_id", "team", "cidr", "segment", "public"]
  }

  files = {
    names = [for region in local.region_names : "config/${region}.yml" if !can(regex("^[a-z]{2}-[a-z]+-[0-9]$", region))]
    shape = [
      for region, d in local.region_files : "config/${region}.yml"
      if !can(keys(d)) || !alltrue([for k in try(keys(d), []) : contains(local.allowed_keys.file, k)]) || !can(keys(d.hub)) || !can(keys(try(d.vpcs, {})))
    ]
    reserved = [for region, d in local.region_files : "config/${region}.yml" if contains(try(keys(d.vpcs), []), "shared")]
    zones = [
      for region, d in local.region_files : "config/${region}.yml"
      if !can(tolist(d.zones)) || length(try(d.zones, [])) < 2 || length(distinct(try(d.zones, []))) != length(try(d.zones, []))
      || !alltrue([for zone in try(d.zones, []) : can(regex("^[a-z]+[0-9]+-az[1-6]$", zone))])
      || length(distinct([for zone in try(d.zones, []) : try(split("-", zone)[0], "")])) > 1
    ]
  }

  problems = {
    shape = [
      for key, d in local.vpc_definitions : key
      if !can(keys(d)) || !alltrue([for k in try(keys(d), []) : contains(local.allowed_keys[local.purposes[key]], k)])
    ]
    cidr = [
      for key, d in local.vpc_definitions : key
      if !can(cidrnetmask(d.cidr)) || try(cidrsubnet(d.cidr, 0, 0) != d.cidr, true) || try(split("/", d.cidr)[1] != (local.purposes[key] == "egress" ? "20" : "16"), true)
    ]
    segment = [for key, d in local.vpc_definitions : key if local.purposes[key] == "spoke" && !contains(local.segments, try(d.segment, ""))]
    public  = [for key, d in local.vpc_definitions : key if local.purposes[key] == "spoke" && !can(tobool(d.public))]
    primary = [for key, d in local.vpc_definitions : key if local.purposes[key] == "egress" && !can(tobool(try(d.primary, false)))]
    referencing = [
      for key, d in local.vpc_definitions : key
      if local.purposes[key] == "egress" && !can(tobool(try(d.security_group_referencing, false)))
    ]
    asn = [
      for key, d in local.vpc_definitions : key
      if local.purposes[key] == "egress" && !try(d.amazon_side_asn >= 64512 && d.amazon_side_asn <= 65534 && floor(d.amazon_side_asn) == d.amazon_side_asn, false)
    ]
  }

  conflicts = {
    account = [
      for environment in distinct([for key in keys(local.vpc_definitions) : split("/", key)[0]]) : environment
      if length(distinct(compact([for key, d in local.vpc_definitions : try(tostring(d.account_id), "") if split("/", key)[0] == environment]))) > 1
    ]
    team = [
      for environment in distinct([for key in keys(local.vpc_definitions) : split("/", key)[0]]) : environment
      if length(distinct(compact([for key, d in local.vpc_definitions : try(tostring(d.team), "") if split("/", key)[0] == environment]))) > 1
    ]
    primary = length([for v in local.vpcs : v if v.primary]) == 1 ? [] : [for key, v in local.vpcs : key if v.purpose == "egress"]
    asn_reused = [
      for asn in distinct([for v in local.vpcs : v.amazon_side_asn if v.amazon_side_asn != null]) : tostring(asn)
      if length([for v in local.vpcs : v if v.amazon_side_asn == asn]) > 1
    ]
    outside = [
      for key, r in local.ranges : key
      if r.start < local.to_range[local.internal_cidr].start || r.start + r.size > local.to_range[local.internal_cidr].start + local.to_range[local.internal_cidr].size
    ]
    overlap = flatten([
      for i, a in local.range_keys : [
        for b in slice(local.range_keys, i + 1, length(local.range_keys)) : "${local.labels[a]} and ${local.labels[b]}"
        if local.ranges[a].start < local.ranges[b].start + local.ranges[b].size && local.ranges[b].start < local.ranges[a].start + local.ranges[a].size
      ]
    ])
  }

  vpcs = {
    for key, d in local.vpc_definitions : key => {
      cidr            = d.cidr
      purpose         = local.purposes[key]
      segment         = local.purposes[key] == "egress" ? "shared" : d.segment
      public          = local.purposes[key] == "egress" ? true : tobool(d.public)
      amazon_side_asn = local.purposes[key] == "egress" ? d.amazon_side_asn : null
      primary         = local.purposes[key] == "egress" ? tobool(try(d.primary, false)) : false
      # Off unless the region's hub turns it on; every VPC in the region follows its hub.
      security_group_referencing = try(tobool(local.region_files[split("/", key)[1]].hub.security_group_referencing), false)
    }
    if !anytrue([for rule in ["names", "shape", "reserved", "zones"] : contains(local.files[rule], "config/${split("/", key)[1]}.yml")])
    && length(local.layout_problems) == 0
    && !anytrue([for rule in ["shape", "cidr", "segment", "public", "asn", "primary"] : contains(local.problems[rule], key)])
    && length(local.problems.referencing) == 0
  }

  ranges     = { for key, v in local.vpcs : key => local.to_range[v.cidr] }
  range_keys = sort(keys(local.ranges))
  to_range = {
    for cidr in distinct(concat([for v in local.vpcs : v.cidr], [local.internal_cidr])) : cidr => {
      start = sum([for i, octet in split(".", split("/", cidr)[0]) : tonumber(octet) * pow(256, 3 - i)])
      size  = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  }

  propagation = {
    restricted = ["restricted", "shared"]
    standard   = ["standard", "shared"]
    shared     = ["restricted", "standard", "shared"]
  }

  # The subnet layout in config/global.yml: per tier, a size and the third octet its block starts at, counted from the VPC's first address.
  # Every tier reserves room for zone_slots zones; zone azN always takes the Nth block, so zones can be added without moving any subnet.
  zone_slots     = 6
  layout_prefix  = { spoke = 16, egress = 20 }
  layout_section = { spoke = "environment", egress = "hub" }
  layout_keys    = { spoke = ["size", "start", "route", "reserved"], egress = ["size", "start"] }
  layout_routes  = ["hub", "internal", "internet", "none"]
  layout_needs   = { spoke = ["transit"], egress = ["public", "transit"] }
  layout_tiers = merge([
    for purpose, section in local.layout_section : {
      for tier, t in try(local.global.subnets[section], {}) : "${purpose}/${tier}" => {
        purpose = purpose
        tier    = tier
        label   = "subnets.${section}.${tier} in config/global.yml"
        keys_ok = can(keys(t)) && alltrue([for k in try(keys(t), []) : contains(local.layout_keys[purpose], k)])
        size    = try(tonumber(t.size), -1)
        start   = try(tonumber(t.start), -1)
        route   = try(tostring(t.route), "")
      }
    }
  ]...)
  layout_checked = {
    for key, t in local.layout_tiers : key => merge(t, {
      size_ok  = t.size == floor(t.size) && t.size > local.layout_prefix[t.purpose] && t.size <= 28
      start_ok = t.start == floor(t.start) && t.start >= 0
      route_ok = t.purpose == "egress" || contains(local.layout_routes, t.route)
      offset   = t.start * 256
      block    = t.size > 0 ? pow(2, 32 - t.size) : 1
    })
  }
  layout_placed = {
    for key, t in local.layout_checked : key => merge(t, {
      aligned = t.size_ok && t.start_ok && t.offset % t.block == 0
      fits    = t.size_ok && t.start_ok && t.offset + local.zone_slots * t.block <= pow(2, 32 - local.layout_prefix[t.purpose])
    })
  }
  layout_usable = [for key, t in local.layout_placed : key if t.keys_ok && t.route_ok && t.aligned && t.fits]
  layout_problems = concat(
    can(keys(local.global.subnets.environment)) && can(keys(local.global.subnets.hub)) ? [] : ["config/global.yml needs subnets.environment and subnets.hub"],
    flatten([
      for purpose, needed in local.layout_needs : [
        for tier in needed : "subnets.${local.layout_section[purpose]} in config/global.yml needs a ${tier} tier"
        if !contains(keys(try(local.global.subnets[local.layout_section[purpose]], {})), tier)
      ]
    ]),
    [for key, t in local.layout_placed : "${t.label}: unknown key (a tier has size, start${t.purpose == "spoke" ? ", route and reserved" : ""})" if !t.keys_ok],
    [
      for key, t in local.layout_placed : "${t.label}: reserved is a prefix length smaller than the subnet (/${t.size}) and no smaller than /28"
      if t.purpose == "spoke" && try(local.global.subnets.environment[t.tier].reserved, null) != null && !try(local.global.subnets.environment[t.tier].reserved > t.size && local.global.subnets.environment[t.tier].reserved <= 28, false)
    ],
    [for key, t in local.layout_placed : "${t.label}: size must be a whole number from ${local.layout_prefix[t.purpose] + 1} to 28" if !t.size_ok],
    [for key, t in local.layout_placed : "${t.label}: start must be a whole number, 0 or more" if !t.start_ok],
    [for key, t in local.layout_placed : "${t.label}: route must be hub, internal, internet or none" if !t.route_ok],
    [for key, t in local.layout_placed : "${t.label}: start ${t.start} is not on a /${t.size} boundary" if t.size_ok && t.start_ok && !t.aligned],
    [for key, t in local.layout_placed : "${t.label}: room for ${local.zone_slots} zones runs past the end of the /${local.layout_prefix[t.purpose]}" if t.aligned && !t.fits],
    [for key, t in local.layout_placed : "${t.label}: the transit tier holds only the hub attachment, so its route is none" if t.purpose == "spoke" && t.tier == "transit" && t.route != "none"],
    flatten([
      for i, a in local.layout_usable : [
        for b in slice(local.layout_usable, i + 1, length(local.layout_usable)) :
        "${local.layout_placed[a].label} and subnets.${local.layout_section[local.layout_placed[b].purpose]}.${local.layout_placed[b].tier} overlap"
        if local.layout_placed[a].purpose == local.layout_placed[b].purpose
        && local.layout_placed[a].offset < local.layout_placed[b].offset + local.zone_slots * local.layout_placed[b].block
        && local.layout_placed[b].offset < local.layout_placed[a].offset + local.zone_slots * local.layout_placed[a].block
      ]
    ]),
  )


  networks = {
    for key, vpc in local.vpcs : key => {
      cidr                       = vpc.cidr
      purpose                    = vpc.purpose
      segment                    = vpc.segment
      propagates_to              = local.propagation[vpc.segment]
      public                     = vpc.public
      amazon_side_asn            = vpc.amazon_side_asn
      primary                    = vpc.primary
      security_group_referencing = vpc.security_group_referencing
      # The account it is built in: its own account_id, else config/global.yml's.
      account_id = try(tostring(local.vpc_definitions[key].account_id), "") != "" ? tostring(local.vpc_definitions[key].account_id) : try(tostring(local.global.account_id), "")
      zones      = local.region_files[split("/", key)[1]].zones
      subnets = {
        for tier, t in local.global.subnets[local.layout_section[vpc.purpose]] :
        tier => [
          for zone in local.region_files[split("/", key)[1]].zones :
          cidrsubnet(vpc.cidr, t.size - local.layout_prefix[vpc.purpose], t.start * 256 / pow(2, 32 - t.size) + tonumber(regex("az([0-9]+)$", zone)[0]) - 1)
        ]
        if vpc.purpose == "egress" || try(t.route, "") != "internet" || vpc.public
      }
      # The second block of the reserved size in each subnet (.64-.127 for a /26): kept for addresses people choose, never handed out by AWS.
      reserved = vpc.purpose == "egress" ? {} : {
        for tier, t in local.global.subnets.environment : tier => [
          for zone in local.region_files[split("/", key)[1]].zones :
          cidrsubnet(cidrsubnet(vpc.cidr, t.size - 16, t.start * 256 / pow(2, 32 - t.size) + tonumber(regex("az([0-9]+)$", zone)[0]) - 1), t.reserved - t.size, 1)
        ]
        if try(t.reserved, null) != null && (try(t.route, "") != "internet" || vpc.public)
      }
      routes = vpc.purpose == "egress" ? {} : {
        for tier, t in local.global.subnets.environment : tier => t.route
        if t.route != "internet" || vpc.public
      }
    }
  }

  internal_cidr = "10.0.0.0/8"
  # Named address groups for security group rules, and DNS forwarding to HQ, from config/global.yml; both built in each hub.
  prefix_lists = {
    for name, entries in coalesce(try(local.global.prefix_lists, null), {}) : name => [
      for e in entries : { cidr = e.cidr, description = e.description }
    ]
  }
  dns = {
    inbound       = try(tobool(local.global.dns.inbound), false)
    forward       = { for domain, targets in coalesce(try(local.global.dns.forward, null), {}) : domain => [for ip in targets : tostring(ip)] }
    private_zones = toset(coalesce(try(local.global.dns.private_zones, null), []))
  }

  hq = {
    ip_address = try(local.global.hq.ip_address, null)
    bgp_asn    = try(local.global.hq.bgp_asn, null)
    cidrs      = try(tolist(local.global.hq.cidrs), [])
  }
}
