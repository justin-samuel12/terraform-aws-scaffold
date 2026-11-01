locals {
  config_dir = coalesce(var.config_dir, path.root)
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  file_keys = ["description", "load_balancer", "ingress", "egress"]
  rule_keys = ["description", "port", "ports", "protocol", "from", "to"]

  # Each rule in a file, expanded to one entry per port range and per address or group its sources stand for.
  expanded = {
    for name, f in local.files : name => {
      for direction in ["ingress", "egress"] : direction => try(f[direction], null) == null ? null : flatten([
        for r in f[direction] : [
          for range in(try(r.protocol, "tcp") == "all" ? [{ from = null, to = null }] : concat(
            can(r.port) ? [{ from = tonumber(r.port), to = tonumber(r.port) }] : [],
            [for p in try(tolist(r.ports), can(r.ports) ? [r.ports] : []) : {
              from = tonumber(split("-", tostring(p))[0])
              to   = tonumber(reverse(split("-", tostring(p)))[0])
            }],
            )) : [
            for source in local.sources[jsonencode(try(r[direction == "ingress" ? "from" : "to"], []))] : {
              description = try(r.description, "")
              protocol    = try(r.protocol, "tcp") == "all" ? "-1" : try(r.protocol, "tcp")
              from_port   = range.from
              to_port     = range.to
              group       = source.group
              cidr        = source.cidr
              prefix_list = source.prefix_list
            }
          ]
        ]
      ])
    }
  }

  # What each list of sources stands for: another group, or the addresses config gives a tier, an environment, HQ or the internet.
  source_lists = distinct(flatten([for f in local.files : [for direction in ["ingress", "egress"] : [for r in try(f[direction], []) : jsonencode(try(r[direction == "ingress" ? "from" : "to"], []))]]]))
  sources = {
    for list in local.source_lists : list => flatten([
      for s in jsondecode(list) : (
        startswith(s, "tier:") ? tolist([for c in try(local.network.subnets[trimprefix(s, "tier:")], []) : { group = null, cidr = c, prefix_list = null }]) :
        startswith(s, "network:") ? tolist([for c in try([module.ip_plan.networks["${trimprefix(s, "network:")}/${var.region}"].cidr], []) : { group = null, cidr = c, prefix_list = null }]) :
        startswith(s, "list:") ? tolist([for id in try([data.aws_ec2_managed_prefix_list.lists[trimprefix(s, "list:")].id], []) : { group = null, cidr = null, prefix_list = id }]) :
        s == "hq" ? tolist([for c in module.ip_plan.hq.cidrs : { group = null, cidr = c, prefix_list = null }]) :
        s == "internet" ? tolist([{ group = null, cidr = "0.0.0.0/0", prefix_list = null }]) :
        tolist([{ group = s, cidr = null, prefix_list = null }])
      )
    ])
  }

  all_sources = distinct(flatten([for list in local.source_lists : jsondecode(list)]))
  list_names  = toset([for s in local.all_sources : trimprefix(s, "list:") if startswith(s, "list:") && contains(keys(module.ip_plan.prefix_lists), trimprefix(s, "list:"))])
  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are description, load_balancer, ingress and egress" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    flatten([for name, f in local.files : [
      for direction in ["ingress", "egress"] : [
        for r in try(f[direction], []) : "${name}.yml: a rule in ${direction} has an unknown key, or no ports for a protocol other than all"
        if !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)]) || (try(r.protocol, "tcp") != "all" && !can(r.port) && !can(r.ports))
      ]
    ]]),
    [for s in local.all_sources : "tier ${trimprefix(s, "tier:")}: ${var.environment}'s VPC in ${var.region} has no such tier" if startswith(s, "tier:") && !contains(keys(local.network.subnets), trimprefix(s, "tier:"))],
    [for s in local.all_sources : "${s}: there is no ${trimprefix(s, "network:")} VPC in ${var.region}" if startswith(s, "network:") && !contains(keys(module.ip_plan.networks), "${trimprefix(s, "network:")}/${var.region}")],
    [for s in local.all_sources : "hq: config/global.yml has no hq.cidrs yet" if s == "hq" && length(module.ip_plan.hq.cidrs) == 0],
    [for s in local.all_sources : "${s}: config/global.yml has no prefix list named ${trimprefix(s, "list:")}" if startswith(s, "list:") && !contains(keys(module.ip_plan.prefix_lists), trimprefix(s, "list:"))],
  )

  groups = {
    for name, f in local.files : name => {
      description   = try(f.description, "")
      load_balancer = try(f.load_balancer, false)
      ingress       = coalesce(local.expanded[name].ingress, [])
      egress        = local.expanded[name].egress
    }
  }
}
