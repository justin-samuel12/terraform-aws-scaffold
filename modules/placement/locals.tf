locals {
  zone_numbers = [for n in sort([for zone in var.network.zones : regex("az([0-9]+)$", zone)[0]]) : tonumber(n)]

  names = {
    for group, f in var.groups : group => [
      for i in range(try(f.count, max(length(try(f.members, {})), 1))) :
      can(f.server_name) ? format("%s%02d", tostring(f.server_name), i + 1) : format("%s-%02d", group, i + 1)
    ]
  }
  all_names = flatten(values(local.names))

  zones   = length(local.zone_numbers)
  tier_of = { for group, f in var.groups : group => try(tostring(f.tier), "private") }
  tiers   = distinct(values(local.tier_of))
  sorted  = sort(keys(var.groups))
  slots = {
    for name, found in { for s in flatten([for group in local.sorted : [for name in local.names[group] : { name = name, group = group }]]) : s.name => s... } :
    name => found[0]
  }
  parse = {
    for name, subnet in merge(
      { for name, s in local.slots : name => var.existing[name] if can(var.existing[name]) },
      { for name, s in local.slots : name => tostring(var.groups[s.group].members[name].subnet_id) if can(var.groups[s.group].members[name].subnet_id) },
      ) : name => {
      subnet = subnet
      tier   = try(regex("^(.+)-az([0-9]+)$", subnet)[0], "")
      zone   = try(index(local.zone_numbers, tonumber(regex("^(.+)-az([0-9]+)$", subnet)[1])), -1)
    }
  }
  pinned = { for name, s in local.slots : name => local.parse[name].subnet if can(var.groups[s.group].members[name].subnet_id) }
  kept   = { for name, s in local.slots : name => var.existing[name] if !can(local.pinned[name]) && can(var.existing[name]) && local.parse[name].tier == local.tier_of[s.group] && local.parse[name].zone >= 0 }
  fixed  = { for name, subnet in merge(local.kept, local.pinned) : name => merge(local.parse[name], { group = local.slots[name].group }) }

  load    = { for t in local.tiers : t => [for z in range(local.zones) : length([for name, f in local.fixed : name if f.tier == t && f.zone == z])] }
  mine    = { for group in local.sorted : group => [for z in range(local.zones) : length([for name, f in local.fixed : name if f.group == group && f.tier == local.tier_of[group] && f.zone == z])] }
  by_load = { for t in local.tiers : t => [for k in sort([for z in range(local.zones) : format("%06d-%02d", local.load[t][z], z)]) : tonumber(split("-", k)[1])] }

  new_servers = { for group in local.sorted : group => [for name in local.names[group] : name if !can(local.fixed[name]) && local.slots[name].group == group] }
  position = {
    for k, group in local.sorted : group => sum(concat([0], [for j, other in local.sorted : length(local.new_servers[other]) if j < k && local.tier_of[other] == local.tier_of[group]]))
  }
  rotation = { for group in local.sorted : group => [for j in range(local.zones) : local.by_load[local.tier_of[group]][(local.position[group] + j) % local.zones]] }
  fill = {
    for group in local.sorted : group => flatten([
      for level in range(max(concat([0], local.mine[group])...) + length(local.new_servers[group]) + 1) : [
        for z in local.rotation[group] : z if local.mine[group][z] <= level
      ]
    ])
  }
  subnets = merge(
    { for name, f in local.fixed : name => f.subnet },
    merge([for group in local.sorted : { for i, name in local.new_servers[group] : name => "${local.tier_of[group]}-az${local.zone_numbers[local.fill[group][i]]}" }]...),
  )

  servers = {
    for name, s in local.slots : name => {
      group         = s.group
      index         = format("%02d", index(local.names[s.group], name) + 1)
      explicit      = can(local.pinned[name])
      subnet        = local.subnets[name]
      type          = try(var.groups[s.group].members[name].instance_type, try(var.groups[s.group].instance_type, null))
      private_ip    = try(tostring(var.groups[s.group].members[name].private_ip), null)
      secondary_ips = try([for a in tolist(var.groups[s.group].members[name].secondary_private_ips) : tostring(a)], [])
    }
  }

  placed = {
    for name, s in local.servers : name => merge(s, {
      tier       = try(regex("^(.+)-az([0-9]+)$", s.subnet)[0], "")
      zone_index = try(index(local.zone_numbers, tonumber(regex("^(.+)-az([0-9]+)$", s.subnet)[1])), -1)
    })
  }

  chosen = {
    for name, s in local.placed : name => [
      for a in concat(s.private_ip == null ? [] : [s.private_ip], s.secondary_ips) :
      can(regex("^[0-9]+$", a)) ? try(cidrhost(var.network.subnets[s.tier][s.zone_index], tonumber(a)), a) : a
    ]
  }

  addressed = {
    for name, s in local.placed : name => merge(s, {
      reserved      = try(var.network.reserved[s.tier][s.zone_index], null)
      addresses     = local.chosen[name]
      private_ip    = s.private_ip == null ? null : local.chosen[name][0]
      secondary_ips = s.private_ip == null ? local.chosen[name] : slice(local.chosen[name], 1, length(local.chosen[name]))
    })
  }

  all_addresses = flatten([for s in values(local.addressed) : s.addresses])
  as_number     = { for a in distinct(concat([for a in local.all_addresses : a if can(cidrhost("${a}/32", 0))], flatten([for s in values(local.addressed) : s.reserved == null ? [] : [cidrhost(s.reserved, 0), cidrhost(s.reserved, -1)]]))) : a => sum([for i, o in split(".", a) : tonumber(o) * pow(256, 3 - i)]) }

  problems = concat(
    [for name in distinct(local.all_names) : "${name}: two servers would have this name; give one group another server_name" if length([for n in local.all_names : n if n == name]) > 1],
    [for name in distinct(local.all_names) : "${name}: a server's name is a host name: lowercase letters, digits and hyphens, at most 63" if !can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))],
    flatten([for group, f in var.groups : [for m in keys(try(f.members, {})) : "${group}: ${m} is not one of its ${try(f.count, 1)} servers" if try(local.servers[m].group, "") != group]]),
    [for name, s in local.placed : "${name}: subnet ${s.subnet}: ${var.label} has no such tier or zone" if !contains(keys(var.network.subnets), s.tier) || s.zone_index < 0],
    flatten([for name, s in local.addressed : [
      for a in s.addresses : "${name}: address ${a} is outside ${s.subnet}'s reserved block ${coalesce(s.reserved, "(none: this tier reserves no addresses)")}"
      if s.reserved == null || try(local.as_number[a] < local.as_number[cidrhost(s.reserved, 0)] || local.as_number[a] > local.as_number[cidrhost(s.reserved, -1)], true)
    ]]),
    [for a in distinct(local.all_addresses) : "address ${a} is chosen twice" if length([for x in local.all_addresses : x if x == a]) > 1],
  )
}
