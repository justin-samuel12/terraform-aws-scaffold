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

  segments     = ["restricted", "standard", "shared"]
  connectivity = ["transit_gateway", "peering"]
  allowed_keys = {
    file   = ["zones", "hub", "vpcs"]
    egress = ["account_id", "team", "cidr", "amazon_side_asn", "primary", "security_group_referencing", "resolver"]
    spoke  = ["account_id", "team", "cidr", "segment", "public", "connectivity"]
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
    connectivity = [for key, d in local.vpc_definitions : key if local.purposes[key] == "spoke" && !contains(local.connectivity, try(tostring(d.connectivity), "transit_gateway"))]
    segment = [
      for key, d in local.vpc_definitions : key
      if local.purposes[key] == "spoke" && (try(tostring(d.connectivity), "transit_gateway") == "peering" ? try(d.segment, null) != null : !contains(local.segments, try(d.segment, "")))
    ]
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
      cidr                       = d.cidr
      purpose                    = local.purposes[key]
      connectivity               = local.purposes[key] == "egress" ? "transit_gateway" : try(tostring(d.connectivity), "transit_gateway")
      segment                    = local.purposes[key] == "egress" ? "shared" : try(tostring(d.connectivity), "transit_gateway") == "peering" ? null : d.segment
      public                     = local.purposes[key] == "egress" ? true : tobool(d.public)
      amazon_side_asn            = local.purposes[key] == "egress" ? d.amazon_side_asn : null
      primary                    = local.purposes[key] == "egress" ? tobool(try(d.primary, false)) : false
      security_group_referencing = try(tobool(local.region_files[split("/", key)[1]].hub.security_group_referencing), false)
    }
    if !anytrue([for rule in ["names", "shape", "reserved", "zones"] : contains(local.files[rule], "config/${split("/", key)[1]}.yml")])
    && length(local.layout_problems) == 0
    && !anytrue([for rule in ["shape", "cidr", "connectivity", "segment", "public", "asn", "primary"] : contains(local.problems[rule], key)])
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
      connectivity               = vpc.connectivity
      segment                    = vpc.segment
      propagates_to              = vpc.segment == null ? [] : local.propagation[vpc.segment]
      public                     = vpc.public
      amazon_side_asn            = vpc.amazon_side_asn
      primary                    = vpc.primary
      security_group_referencing = vpc.security_group_referencing
      resolver                   = local.resolvers[split("/", key)[1]]
      account_id                 = try(tostring(local.vpc_definitions[key].account_id), "") != "" ? tostring(local.vpc_definitions[key].account_id) : try(tostring(local.global.account_id), "")
      zones                      = local.region_files[split("/", key)[1]].zones
      subnets = {
        for tier, t in local.global.subnets[local.layout_section[vpc.purpose]] :
        tier => [
          for zone in local.region_files[split("/", key)[1]].zones :
          cidrsubnet(vpc.cidr, t.size - local.layout_prefix[vpc.purpose], t.start * 256 / pow(2, 32 - t.size) + tonumber(regex("az([0-9]+)$", zone)[0]) - 1)
        ]
        if vpc.purpose == "egress" || try(t.route, "") != "internet" || vpc.public
      }
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
  prefix_lists = {
    for name, entries in coalesce(try(local.global.prefix_lists, null), {}) : name => [
      for e in entries : { cidr = e.cidr, description = e.description }
    ]
  }
  dns = {
    inbound        = try(tobool(local.global.dns.inbound), false)
    forward        = merge({}, [for name, site in local.sites : site.forward]...)
    private_zones  = toset(compact(concat(tolist(coalesce(try(local.global.dns.private_zones, null), [])), [local.private_domain])))
    public_domains = local.public_domains
    private_domain = local.private_domain
    resolve_all    = [for env in coalesce(try(local.global.dns.resolve_all_private, null), []) : tostring(env)]
  }
  private_domain = try(tostring(local.global.dns.private_domain), null)
  public_domains = [for d in try(tolist(local.global.dns.public_domain), []) : try(tostring(d), "")]

  environment_names = distinct([for key in keys(local.vpc_definitions) : split("/", key)[0] if split("/", key)[0] != "shared"])
  zones = {
    for env in local.environment_names : env => {
      private = local.dns.private_domain == null ? null : "${env}.${local.dns.private_domain}"
    }
  }

  site_files = try({ for name, site in local.global.sites : name => site }, {})
  all_sites = {
    for name, site in local.site_files : name => {
      enabled      = try(tobool(site.enabled), true)
      ip_addresses = try(site.ip_address, null) == null ? [] : try([tostring(site.ip_address)], [for ip in tolist(site.ip_address) : tostring(ip)], ["-"])
      bgp_asn      = try(tonumber(site.bgp_asn), null)
      cidrs        = try([for c in tolist(site.cidrs) : tostring(c)], [])
      forward      = { for domain, targets in try(tomap(site.forward), {}) : domain => [for ip in targets : tostring(ip)] }
    }
  }
  sites               = { for name, site in local.all_sites : name => { ip_addresses = site.ip_addresses, bgp_asn = site.bgp_asn, cidrs = site.cidrs, forward = site.forward } if site.enabled }
  site_keys           = ["enabled", "ip_address", "bgp_asn", "cidrs", "forward"]
  site_cidrs          = distinct(flatten([for name, site in local.sites : site.cidrs]))
  resolver_files      = { for region, d in local.region_files : region => try(d.hub.resolver, null) }
  resolve_all_regions = toset([for key, v in local.vpcs : split("/", key)[1] if contains(local.dns.resolve_all, split("/", key)[0])])
  directory_file      = try(local.global.directory, null)
  directory_keys      = ["enabled", "name", "short_name", "edition", "description"]
  directory = local.directory_file == null || !try(tobool(local.directory_file.enabled), true) ? null : {
    name        = try(tostring(local.directory_file.name), "")
    short_name  = try(tostring(local.directory_file.short_name), "")
    edition     = try(tostring(local.directory_file.edition), "")
    description = try(tostring(local.directory_file.description), "")
  }
  primary_region_name = try(one([for key, v in local.vpcs : split("/", key)[1] if v.purpose == "egress" && v.primary]), null)
  resolvers = {
    for region, r in local.resolver_files : region => {
      inbound  = local.dns.inbound && try(tobool(r.inbound), try(local.vpcs["shared/${region}"].primary, false))
      outbound = try(tobool(r.outbound), true) && (length(local.dns.forward) > 0 || contains(local.resolve_all_regions, region) || (local.directory != null && region == local.primary_region_name))
      domains  = try(tobool(r.outbound), true) ? sort(concat(keys(local.dns.forward), local.directory != null && region == local.primary_region_name ? [local.directory.name] : [])) : []
    }
  }
  directory_problems = local.directory_file == null ? [] : concat(
    [for x in [1] : "directory in config/global.yml: keys are ${join(", ", local.directory_keys)}" if !can(keys(local.directory_file)) || !alltrue([for k in try(keys(local.directory_file), []) : contains(local.directory_keys, k)])],
    [for x in [1] : "directory in config/global.yml: enabled is true or false" if try(local.directory_file.enabled, null) != null && !can(tobool(try(local.directory_file.enabled, null)))],
    local.directory == null ? [] : concat(
      [for x in [1] : "directory.name in config/global.yml: the domain's DNS name, such as ad.example.internal" if !can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", local.directory.name))],
      [for x in [1] : "directory.short_name in config/global.yml: the NetBIOS name, up to 15 letters, digits and hyphens, such as CORP" if !can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,14}$", local.directory.short_name))],
      [for x in [1] : "directory.edition in config/global.yml: Standard or Enterprise" if !contains(["Standard", "Enterprise"], local.directory.edition)],
      [for x in [1] : "directory.name in config/global.yml: ${local.directory.name} is already a site's forward; one domain answers in one place" if contains(keys(local.dns.forward), local.directory.name)],
      [for x in [1] : "directory.name in config/global.yml: ${local.directory.name} is a hosted zone of ours; give the domain its own name, such as ad.${coalesce(local.dns.private_domain, "example.internal")}" if contains(concat(tolist(local.dns.private_zones), local.dns.public_domains), local.directory.name)],
      [for x in [1] : "directory in config/global.yml: it is built in the primary hub's dns tier, which needs a hub with primary: true" if local.primary_region_name == null],
    ),
  )
  resolver_problems = concat(
    [for region, r in local.resolver_files : "config/${region}.yml: hub.resolver takes inbound and outbound, each true or false" if r != null && (!can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(["inbound", "outbound"], k) && can(tobool(r[k]))]))],
    [for region in local.resolve_all_regions : "config/${region}.yml: ${join(", ", [for key, v in local.vpcs : split("/", key)[0] if split("/", key)[1] == region && contains(local.dns.resolve_all, split("/", key)[0])])} resolve every private name through this region's hub, which needs hub.resolver inbound and outbound here" if !try(local.resolvers[region].inbound && local.resolvers[region].outbound, false)],
    [for x in [1] : "dns.inbound is true, but no region's hub has an inbound endpoint (hub.resolver.inbound: false everywhere)" if local.dns.inbound && !anytrue([for region, r in local.resolvers : r.inbound])],
  )
  site_ranges = flatten([
    for name, site in local.sites : [
      for cidr in site.cidrs : {
        site  = name
        cidr  = cidr
        start = sum([for i, octet in split(".", split("/", cidr)[0]) : tonumber(octet) * pow(256, 3 - i)])
        size  = pow(2, 32 - tonumber(split("/", cidr)[1]))
      } if can(cidrnetmask(cidr))
    ]
  ])
  site_overlaps = flatten([
    for s in local.site_ranges : [
      for key, r in local.ranges : "${s.site}'s ${s.cidr} and ${key}" if s.start < r.start + r.size && r.start < s.start + s.size
    ]
  ])
  site_forward_domains = flatten([for name, site in local.sites : keys(site.forward)])
}
