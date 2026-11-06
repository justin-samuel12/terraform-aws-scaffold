locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys = ["service_name", "vpc_endpoint_type", "subnet_ids", "security_group_ids", "private_dns_enabled", "route_table_ids", "tags"]
  subnet_names = toset(flatten([
    for tier in keys(local.network.subnets) : [for zone in local.network.zones : "${tier}-${split("-", zone)[1]}"]
  ]))

  parsed = {
    for name, f in local.files : name => {
      service_name        = try(tostring(f.service_name), "")
      vpc_endpoint_type   = try(tostring(f.vpc_endpoint_type), "")
      subnet_ids          = try(f.subnet_ids, null) == null ? [] : try([for s in tolist(f.subnet_ids) : tostring(s)], [])
      security_group_ids  = try(f.security_group_ids, null) == null ? [] : try([for s in tolist(f.security_group_ids) : tostring(s)], [])
      private_dns_enabled = try(tobool(f.private_dns_enabled), null)
      route_table_ids     = try(f.route_table_ids, null) == null ? [] : try([for s in tolist(f.route_table_ids) : tostring(s)], [])
      tags                = try(tomap(f.tags), {})
    }
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); an endpoint's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_vpc_endpoint takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, e in local.parsed : "${name}.yml: service_name is the full name in this region, such as com.amazonaws.${var.region}.ssm" if !startswith(e.service_name, "com.amazonaws.${var.region}.")],
    [for name, e in local.parsed : "${name}.yml: vpc_endpoint_type is Interface or Gateway" if !contains(["Interface", "Gateway"], e.vpc_endpoint_type)],
    [for name, e in local.parsed : "${name}.yml: an Interface endpoint needs subnet_ids in at least two zones, security_group_ids and private_dns_enabled, and no route_table_ids" if e.vpc_endpoint_type == "Interface" && (length(e.subnet_ids) < 2 || length(e.security_group_ids) == 0 || e.private_dns_enabled == null || length(e.route_table_ids) > 0)],
    [for name, e in local.parsed : "${name}.yml: a Gateway endpoint needs route_table_ids, and no subnet_ids, security_group_ids or private_dns_enabled" if e.vpc_endpoint_type == "Gateway" && (length(e.route_table_ids) == 0 || length(e.subnet_ids) > 0 || length(e.security_group_ids) > 0 || e.private_dns_enabled != null)],
    flatten([for name, e in local.parsed : [
      for s in concat(e.subnet_ids, e.route_table_ids) : "${name}.yml: ${s} is not a subnet of ${var.environment}'s VPC in ${var.region} (${join(", ", sort(local.subnet_names))})"
      if !startswith(s, "subnet-") && !startswith(s, "rtb-") && !contains(local.subnet_names, s)
    ]]),
  )

  endpoints = { for name, e in local.parsed : name => e if length(local.problems) == 0 }

  subnets      = toset(flatten([for e in values(local.endpoints) : [for s in concat(e.subnet_ids, e.route_table_ids) : s if !startswith(s, "subnet-") && !startswith(s, "rtb-")]]))
  route_tables = toset(flatten([for e in values(local.endpoints) : [for s in e.route_table_ids : s if !startswith(s, "rtb-")]]))
  groups       = toset(flatten([for e in values(local.endpoints) : [for g in e.security_group_ids : g if !startswith(g, "sg-")]]))
}
