locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys = ["description", "tags", "ingress", "egress"]
  rule_keys = ["description", "ip_protocol", "from_port", "to_port", "cidr_ipv4", "cidr_ipv6", "prefix_list_id", "referenced_security_group_id"]
  peers     = ["cidr_ipv4", "cidr_ipv6", "prefix_list_id", "referenced_security_group_id"]
  remote    = "^[a-z][a-z0-9-]*/[a-z][a-z0-9-]*$"
  kinds     = ["load-balancer", "server", "database", "client", "endpoint"]

  rules = {
    for name, f in local.files : name => {
      for direction in ["ingress", "egress"] : direction => [
        for r in try(f[direction], null) == null ? [] : try(tolist(f[direction]), []) : {
          description                  = try(tostring(r.description), "")
          ip_protocol                  = try(tostring(r.ip_protocol), "")
          from_port                    = try(tonumber(r.from_port), null)
          to_port                      = try(tonumber(r.to_port), null)
          cidr_ipv4                    = try(tostring(r.cidr_ipv4), null)
          cidr_ipv6                    = try(tostring(r.cidr_ipv6), null)
          prefix_list_id               = try(tostring(r.prefix_list_id), null)
          referenced_security_group_id = try(tostring(r.referenced_security_group_id), null)
        }
      ]
    }
  }
  all_rules = flatten([for name, d in local.rules : [for direction, rules in d : [for r in rules : merge(r, { owner = name, direction = direction })]]])

  list_names   = toset([for r in local.all_rules : r.prefix_list_id if r.prefix_list_id != null && !startswith(coalesce(r.prefix_list_id, "-"), "pl-") && contains(keys(module.ip_plan.prefix_lists), coalesce(r.prefix_list_id, "-"))])
  remote_refs  = distinct([for r in local.all_rules : r.referenced_security_group_id if can(regex(local.remote, coalesce(r.referenced_security_group_id, "-")))])
  remote_names = toset([for ref in local.remote_refs : ref if local.network.security_group_referencing && contains(keys(module.ip_plan.networks), "${split("/", ref)[0]}/${var.region}") && split("/", ref)[0] != var.environment])

  resolved = {
    for name, d in local.rules : name => {
      for direction, rules in d : direction => [
        for r in rules : merge(r, {
          prefix_list_id               = r.prefix_list_id == null ? null : startswith(r.prefix_list_id, "pl-") ? r.prefix_list_id : try(data.aws_ec2_managed_prefix_list.lists[r.prefix_list_id].id, null)
          referenced_security_group_id = r.referenced_security_group_id == null ? null : can(regex(local.remote, r.referenced_security_group_id)) ? try(data.aws_security_group.remote[r.referenced_security_group_id].id, null) : r.referenced_security_group_id
        })
      ]
    }
  }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a group's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_security_group takes them" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: description is required" if trimspace(try(tostring(f.description), "")) == ""],
    [for name, f in local.files : "${name}.yml: tags.Kind is required, one of ${join(", ", local.kinds)}" if !contains(local.kinds, try(tostring(f.tags.Kind), ""))],
    [for name, f in local.files : "${name}.yml: the tags Name and Key are the stack's own; give yours another name" if length(setintersection(keys(try(tomap(f.tags), {})), ["Name", "Key"])) > 0],
    [for name, f in local.files : "${name}.yml: ingress and egress are lists of rules" if anytrue([for d in ["ingress", "egress"] : try(f[d], null) != null && !can(tolist(f[d]))])],
    flatten([for name, f in local.files : [
      for d in ["ingress", "egress"] : [
        for r in try(f[d], null) == null ? [] : try(tolist(f[d]), []) : "${name}.yml: a rule in ${d} takes the arguments of aws_vpc_security_group_${d}_rule: ${join(", ", local.rule_keys)}"
        if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)])
      ]
    ]]),
    [for r in local.all_rules : "${r.owner}.yml: the ${r.direction} rule \"${r.description}\" needs ip_protocol (tcp, udp, icmp, icmpv6 or -1)" if r.ip_protocol == ""],
    [for r in local.all_rules : "${r.owner}.yml: the ${r.direction} rule \"${r.description}\" needs from_port and to_port, unless ip_protocol is -1" if !contains(["", "-1"], r.ip_protocol) && (r.from_port == null || r.to_port == null)],
    [for r in local.all_rules : "${r.owner}.yml: the ${r.direction} rule \"${r.description}\" names exactly one of ${join(", ", local.peers)}" if length(compact([for p in local.peers : r[p]])) != 1],
    [for r in local.all_rules : "${r.owner}.yml: referenced_security_group_id ${r.referenced_security_group_id} is not a group in this stack (a file named ${r.referenced_security_group_id}.yml)" if r.referenced_security_group_id != null && !startswith(coalesce(r.referenced_security_group_id, "-"), "sg-") && !can(regex(local.remote, coalesce(r.referenced_security_group_id, "-"))) && !contains(keys(local.files), coalesce(r.referenced_security_group_id, "-"))],
    [for r in local.all_rules : "${r.owner}.yml: prefix_list_id ${r.prefix_list_id} is not a prefix list in config/global.yml" if r.prefix_list_id != null && !startswith(coalesce(r.prefix_list_id, "-"), "pl-") && !contains(keys(module.ip_plan.prefix_lists), coalesce(r.prefix_list_id, "-"))],
    [for ref in local.remote_refs : "referenced_security_group_id ${ref}: security group referencing is off in ${var.region}; turn it on with hub.security_group_referencing: true in config/${var.region}.yml, or use cidr_ipv4 or prefix_list_id" if !local.network.security_group_referencing],
    [for ref in local.remote_refs : "referenced_security_group_id ${ref}: there is no ${split("/", ref)[0]} VPC in ${var.region}" if !contains(keys(module.ip_plan.networks), "${split("/", ref)[0]}/${var.region}")],
    [for ref in local.remote_refs : "referenced_security_group_id ${ref}: ${var.environment}'s own groups are named without ${var.environment}/" if split("/", ref)[0] == var.environment],
  )

  groups = {
    for name, f in local.files : name => {
      description = try(tostring(f.description), "")
      tags        = try(tomap(f.tags), {})
      ingress     = local.resolved[name].ingress
      egress      = local.resolved[name].egress
    }
  }
}
