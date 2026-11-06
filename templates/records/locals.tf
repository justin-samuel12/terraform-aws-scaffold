locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys  = ["zone_id", "name", "type", "ttl", "records", "alias"]
  alias_keys = ["name", "zone_id", "evaluate_target_health"]
  types      = ["A", "AAAA", "CNAME", "TXT"]
  zone_id    = "^Z[A-Z0-9]+$"
  ip         = "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"

  own_zone      = try(module.ip_plan.zones[var.environment].private, null)
  private_zones = concat(compact([local.own_zone]), tolist(module.ip_plan.dns.private_zones))

  parsed = {
    for n, f in local.files : n => {
      zone_id = try(tostring(f.zone_id), "")
      name    = try(tostring(f.name), "")
      type    = try(tostring(f.type), "")
      ttl     = try(tonumber(f.ttl), null)
      records = try(f.records, null) == null ? [] : try([for r in tolist(f.records) : tostring(r)], [])
      alias = try(f.alias, null) == null ? null : {
        name                   = try(tostring(f.alias.name), "")
        zone_id                = try(tostring(f.alias.zone_id), "")
        evaluate_target_health = try(tobool(f.alias.evaluate_target_health), null)
      }
    }
  }

  placed = {
    for n, r in local.parsed : n => merge(r, {
      by_id   = can(regex(local.zone_id, r.zone_id))
      private = contains(local.private_zones, r.zone_id)
      own     = r.zone_id == local.own_zone
    })
  }

  problems = concat(
    [for n, paths in local.found : "${n}.yml is in more than one folder (${join(", ", sort(paths))}); a record's name is its file's, so it must be unique" if length(paths) > 1],
    [for n, f in local.files : "${n}.yml: keys are ${join(", ", local.file_keys)}, as aws_route53_record takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for n, f in local.files : "${n}.yml: alias takes ${join(", ", local.alias_keys)}" if try(f.alias, null) != null && (!can(keys(f.alias)) || !alltrue([for k in try(keys(f.alias), []) : contains(local.alias_keys, k)]))],
    [for n, r in local.parsed : "${n}.yml: zone_id is required: the hosted zone's name, such as example.com, or its id" if r.zone_id == ""],
    [for n, r in local.parsed : "${n}.yml: name is required, written in full (api.example.com)" if r.name == ""],
    [for n, r in local.parsed : "${n}.yml: type is one of ${join(", ", local.types)}" if !contains(local.types, r.type)],
    [for n, r in local.placed : "${n}.yml: ${r.name} is not in the zone ${r.zone_id}" if r.name != "" && r.zone_id != "" && !r.by_id && r.name != r.zone_id && !endswith(r.name, ".${r.zone_id}")],
    [for n, r in local.placed : "${n}.yml: ${r.zone_id} is not a private zone nor one of dns.public_domain in config/global.yml" if r.zone_id != "" && !r.by_id && !r.private && !contains(module.ip_plan.dns.public_domains, r.zone_id)],
    [for n, r in local.parsed : "${n}.yml: a record has either alias or ttl with records, not both" if(r.alias != null) == (r.ttl != null || length(r.records) > 0)],
    [for n, r in local.parsed : "${n}.yml: without alias, ttl and records are both required" if r.alias == null && (r.ttl == null || length(r.records) == 0)],
    [for n, r in local.parsed : "${n}.yml: alias needs name (a load balancer in this environment, or a DNS name), zone_id (that load balancer's name again, or the target's hosted zone id) and evaluate_target_health" if r.alias != null && (try(r.alias.name, "") == "" || try(r.alias.zone_id, "") == "" || try(r.alias.evaluate_target_health, null) == null)],
  )

  load_balancers = toset(compact(flatten([
    for r in values(local.records) : r.alias == null ? [] : [
      strcontains(r.alias.name, ".") ? "" : r.alias.name,
      can(regex(local.zone_id, r.alias.zone_id)) ? "" : r.alias.zone_id,
    ]
  ])))
  servers = toset(flatten([for r in values(local.records) : [for v in r.records : v if r.type == "A" && !can(regex(local.ip, v))]]))

  records = { for n, r in local.placed : n => r if length(local.problems) == 0 }
}
