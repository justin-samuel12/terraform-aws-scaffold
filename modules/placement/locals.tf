locals {
  # By zone number, never by the order config lists zones in, so reordering the list moves no server.
  zone_numbers = [for n in sort([for zone in var.network.zones : regex("az([0-9]+)$", zone)[0]]) : tonumber(n)]

  # Every server: named <group>-NN, in its pinned subnet or spread across the zones in turn, with its chosen addresses turned into real ones.
  servers = merge([
    for group, f in var.groups : {
      for i in range(try(f.count, max(length(try(f.members, {})), 1))) : format("%s-%02d", group, i + 1) => {
        group    = group
        explicit = can(f.members[format("%s-%02d", group, i + 1)].subnet)
        subnet   = try(f.members[format("%s-%02d", group, i + 1)].subnet, "${try(f.tier, "private")}-az${local.zone_numbers[i % length(local.zone_numbers)]}")
        type     = try(f.members[format("%s-%02d", group, i + 1)].instance_type, try(f.instance_type, null))
        hosts = try(
          f.members[format("%s-%02d", group, i + 1)].ips,
          can(f.members[format("%s-%02d", group, i + 1)].ip) ? { primary = f.members[format("%s-%02d", group, i + 1)].ip } : {},
        )
      }
    }
  ]...)

  placed = {
    for name, s in local.servers : name => merge(s, {
      tier       = try(regex("^(.+)-az([0-9]+)$", s.subnet)[0], "")
      zone_index = try(index(local.zone_numbers, tonumber(regex("^(.+)-az([0-9]+)$", s.subnet)[1])), -1)
    })
  }

  addressed = {
    for name, s in local.placed : name => merge(s, {
      reserved  = try(var.network.reserved[s.tier][s.zone_index], null)
      addresses = { for role, host in s.hosts : role => try(cidrhost(var.network.subnets[s.tier][s.zone_index], host), null) }
    })
  }

  as_number     = { for a in distinct(compact(flatten([for s in values(local.addressed) : concat(values(s.addresses), s.reserved == null ? [] : [cidrhost(s.reserved, 0), cidrhost(s.reserved, -1)])]))) : a => sum([for i, o in split(".", a) : tonumber(o) * pow(256, 3 - i)]) }
  all_addresses = compact(flatten([for s in values(local.addressed) : values(s.addresses)]))

  problems = concat(
    flatten([for group, f in var.groups : [for m in keys(try(f.members, {})) : "${group}: ${m} is not one of its ${try(f.count, 1)} servers" if try(local.servers[m].group, "") != group]]),
    [for name, s in local.placed : "${name}: subnet ${s.subnet}: ${var.label} has no such tier or zone" if !contains(keys(var.network.subnets), s.tier) || s.zone_index < 0],
    flatten([for name, s in local.addressed : [
      for role, a in s.addresses : "${name}: ${role} address ${coalesce(a, "?")} is outside ${s.subnet}'s reserved block ${coalesce(s.reserved, "(none: this tier reserves no addresses)")}"
      if a == null || s.reserved == null || try(local.as_number[a] < local.as_number[cidrhost(s.reserved, 0)] || local.as_number[a] > local.as_number[cidrhost(s.reserved, -1)], true)
    ]]),
    [for a in distinct(local.all_addresses) : "address ${a} is chosen twice" if length([for x in local.all_addresses : x if x == a]) > 1],
  )
}
