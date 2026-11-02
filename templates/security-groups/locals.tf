locals {
  config_dir = coalesce(var.config_dir, path.root)
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  file_keys = ["description", "load_balancer", "ingress", "egress"]
  # A rule is written as the AWS provider writes one (ip_protocol, from_port, to_port); source (ingress) or destination (egress) names what it allows, never a raw ID.
  rule_keys = { ingress = ["description", "ip_protocol", "from_port", "to_port", "source"], egress = ["description", "ip_protocol", "from_port", "to_port", "destination"] }
  peer      = { ingress = "source", egress = "destination" }

  # Each rule in a file, expanded to one entry per address or group its source or destination stands for.
  expanded = {
    for name, f in local.files : name => {
      for direction in ["ingress", "egress"] : direction => try(f[direction], null) == null ? null : flatten([
        for r in f[direction] : [
          for peer in local.sources[jsonencode(try(tolist(r[local.peer[direction]]), [r[local.peer[direction]]], []))] : {
            description     = try(r.description, "")
            protocol        = tostring(try(r.ip_protocol, "tcp"))
            from_port       = tostring(try(r.ip_protocol, "tcp")) == "-1" ? null : try(tonumber(r.from_port), null)
            to_port         = tostring(try(r.ip_protocol, "tcp")) == "-1" ? null : try(tonumber(r.to_port), null)
            group           = peer.group
            cidr            = peer.cidr
            prefix_list     = peer.prefix_list
            remote_group    = peer.remote_group
            remote_group_id = peer.remote_group_id
          }
        ]
      ])
    }
  }

  # What each list of sources stands for: another group, or the addresses config gives a tier, an environment, HQ or the internet.
  source_lists = distinct(flatten([for f in local.files : [for direction in ["ingress", "egress"] : [for r in try(f[direction], []) : jsonencode(try(tolist(r[local.peer[direction]]), [r[local.peer[direction]]], []))]]]))
  sources = {
    for list in local.source_lists : list => flatten([
      for s in jsondecode(list) : (
        startswith(s, "tier:") ? tolist([for c in try(local.network.subnets[trimprefix(s, "tier:")], []) : { group = null, cidr = c, prefix_list = null, remote_group = null, remote_group_id = null }]) :
        startswith(s, "network:") ? tolist([for c in try([module.ip_plan.networks["${trimprefix(s, "network:")}/${var.region}"].cidr], []) : { group = null, cidr = c, prefix_list = null, remote_group = null, remote_group_id = null }]) :
        startswith(s, "list:") ? tolist([for id in try([data.aws_ec2_managed_prefix_list.lists[trimprefix(s, "list:")].id], []) : { group = null, cidr = null, prefix_list = id, remote_group = null, remote_group_id = null }]) :
        startswith(s, "group:") ? tolist([{ group = null, cidr = null, prefix_list = null, remote_group = trimprefix(s, "group:"), remote_group_id = try(data.aws_security_group.remote[trimprefix(s, "group:")].id, null) }]) :
        s == "hq" ? tolist([for c in module.ip_plan.hq.cidrs : { group = null, cidr = c, prefix_list = null, remote_group = null, remote_group_id = null }]) :
        s == "internet" ? tolist([{ group = null, cidr = "0.0.0.0/0", prefix_list = null, remote_group = null, remote_group_id = null }]) :
        tolist([{ group = s, cidr = null, prefix_list = null, remote_group = null, remote_group_id = null }])
      )
    ])
  }

  all_sources = distinct(flatten([for list in local.source_lists : jsondecode(list)]))
  remote_names = toset([
    for s in local.all_sources : trimprefix(s, "group:")
    if startswith(s, "group:") && local.network.security_group_referencing && can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$", trimprefix(s, "group:")))
    && contains(keys(module.ip_plan.networks), "${split("/", trimprefix(s, "group:"))[0]}/${var.region}")
  ])
  list_names = toset([for s in local.all_sources : trimprefix(s, "list:") if startswith(s, "list:") && contains(keys(module.ip_plan.prefix_lists), trimprefix(s, "list:"))])
  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are description, load_balancer, ingress and egress" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    flatten([for name, f in local.files : [
      for direction in ["ingress", "egress"] : [
        for r in try(f[direction], []) : "${name}.yml: a rule in ${direction} takes ${join(", ", local.rule_keys[direction])}; from_port and to_port are both required unless ip_protocol is -1"
        if !alltrue([for k in try(keys(r), []) : contains(local.rule_keys[direction], k)]) || (tostring(try(r.ip_protocol, "tcp")) != "-1" && !(can(tonumber(r.from_port)) && can(tonumber(r.to_port))))
      ]
    ]]),
    [for s in local.all_sources : "tier ${trimprefix(s, "tier:")}: ${var.environment}'s VPC in ${var.region} has no such tier" if startswith(s, "tier:") && !contains(keys(local.network.subnets), trimprefix(s, "tier:"))],
    [for s in local.all_sources : "${s}: there is no ${trimprefix(s, "network:")} VPC in ${var.region}" if startswith(s, "network:") && !contains(keys(module.ip_plan.networks), "${trimprefix(s, "network:")}/${var.region}")],
    [for s in local.all_sources : "hq: config/global.yml has no hq.cidrs yet" if s == "hq" && length(module.ip_plan.hq.cidrs) == 0],
    [for s in local.all_sources : "${s}: a group in another VPC is group:<environment>/<group>" if startswith(s, "group:") && !can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$", trimprefix(s, "group:")))],
    [for s in local.all_sources : "${s}: security group referencing is off in ${var.region}; turn it on with hub.security_group_referencing: true in config/${var.region}.yml, or use network:, tier: or list:" if startswith(s, "group:") && !local.network.security_group_referencing],
    [for s in local.all_sources : "${s}: there is no ${split("/", trimprefix(s, "group:"))[0]} VPC in ${var.region}" if startswith(s, "group:") && can(regex("^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$", trimprefix(s, "group:"))) && !contains(keys(module.ip_plan.networks), "${split("/", trimprefix(s, "group:"))[0]}/${var.region}")],
    [for s in local.all_sources : "${s}: ${var.environment}'s own groups are named without group:" if startswith(s, "group:") && startswith(trimprefix(s, "group:"), "${var.environment}/")],
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
