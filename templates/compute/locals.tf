locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
    if !contains(split("/", path), "deployments")
  }
  file_paths = { for name, paths in local.found : name => sort(paths)[0] }
  raw_files  = { for name, path in local.file_paths : name => yamldecode(file("${local.config_dir}/${path}")) }

  blueprints_dir = abspath(coalesce(var.blueprints_dir, "${var.config_path == null ? "${path.root}/../../../../config" : var.config_path}/../blueprints/compute"))
  scripts_dir    = abspath(coalesce(var.scripts_dir, "${var.config_path == null ? "${path.root}/../../../../config" : var.config_path}/../scripts"))
  amis_dir       = abspath(coalesce(var.amis_dir, "${var.config_path == null ? "${path.root}/../../../../config" : var.config_path}/amis"))
  blueprint_refs = module.blueprint.refs
  blueprints     = module.blueprint.blueprints
  files = merge(module.blueprint.files, {
    for group, ref in local.blueprint_refs : group => merge(
      module.blueprint.files[group],
      can(local.blueprints[ref].role) ? { iam_instance_profile = local.app_role_names[group] } : {},
    ) if can(keys(module.blueprint.files[group]))
  })

  app_role_names    = { for group, ref in local.blueprint_refs : group => "${var.environment}-${group}-${var.region}" if can(local.blueprints[ref].role) }
  app_role_policies = toset(flatten([for group, ref in local.blueprint_refs : [for p in try(tolist(local.blueprints[ref].role.managed_policy_arns), []) : p if !startswith(p, "arn:")] if contains(keys(local.app_role_names), group)]))
  role_keys         = ["managed_policy_arns", "statement"]
  server_keys       = ["count", "server_name", "instance_type", "ami", "tier", "iam_instance_profile", "vpc_security_group_ids", "root_block_device", "ebs_block_device", "user_data", "members", "tags"]
  feature_keys      = ["autoscaling_group", "autoscaling_policy", "target_group", "listener_rule", "target_group_attachments", "route53_records"]
  group_keys        = concat(local.server_keys, local.feature_keys)
  block_keys = {
    target_group  = ["port", "protocol", "slow_start", "health_check", "stickiness"]
    listener_rule = ["listener_arn", "priority", "condition"]
  }
  health_check_keys = ["path", "matcher"]
  stickiness_keys   = ["enabled", "type", "cookie_duration", "cookie_name"]
  attachment_keys   = ["target_group_arn", "port"]
  record_keys       = ["name", "type", "zone_id", "alias"]
  zone_id           = "^Z[0-9A-Z]+$"
  rules_of = {
    for group, f in local.files : group => can(f.listener_rule) ? [{
      load_balancer = try(split("/", tostring(f.listener_rule.listener_arn))[0], "?")
      listener      = try(split("/", tostring(f.listener_rule.listener_arn))[1], "?")
      listener_arn  = try(tostring(f.listener_rule.listener_arn), "")
      host_header   = try(tolist(f.listener_rule.condition.host_header.values), [])
      path_pattern  = try(tolist(f.listener_rule.condition.path_pattern.values), [])
      priority      = try(f.listener_rule.priority, 0)
    }] : []
  }

  codedeploy_raw = {
    for group, f in local.files : group => (
      can(tolist(f.tags.CodeDeploy)) ? [for x in tolist(f.tags.CodeDeploy) : tostring(x)]
      : can(jsondecode(replace(tostring(f.tags.CodeDeploy), "'", "\""))) ? [for x in jsondecode(replace(tostring(f.tags.CodeDeploy), "'", "\"")) : tostring(x)]
      : split(",", replace(replace(tostring(f.tags.CodeDeploy), "[", ""), "]", ""))
    ) if can(f.tags.CodeDeploy) && try(tostring(f.tags.CodeDeploy), "") != "null"
  }
  deploys = flatten([for group, specs in local.codedeploy_raw : [for raw in specs : {
    group       = group
    spec        = trimspace(raw)
    application = lower(split(":", trimspace(raw))[0])
    selector = try({
      key   = regex("^[^:]+:([^=]+)=(.*)$", trimspace(raw))[0]
      value = regex("^[^:]+:([^=]+)=(.*)$", trimspace(raw))[1]
    }, null)
  } if trimspace(raw) != ""]])
  applications          = toset([for d in local.deploys : d.application])
  application_groups    = { for app in local.applications : app => distinct([for d in local.deploys : d.group if d.application == app]) }
  application_selectors = { for app in local.applications : app => distinct([for d in local.deploys : d.selector if d.application == app && d.selector != null]) }
  containerized         = { for app, groups in local.application_groups : app => alltrue([for g in groups : lower(trimspace(try(tostring(local.files[g].tags.isContainerized), ""))) == "true"]) }

  existing = {
    for name, subnets in {
      for r in try(data.aws_resourcegroupstaggingapi_resources.servers[0].resource_tag_mapping_list, []) : try(r.tags["Server"], r.tags["Name"]) => r.tags["Subnet"]...
      if can(try(r.tags["Server"], r.tags["Name"])) && can(r.tags["Subnet"])
    } : name => subnets[0]
  }

  reserved_tags = ["Name", "Server", "Subnet", "Group", "PatchGroup"]
  server_tags = {
    for group, f in local.files : group => merge(
      { for k, v in try(f.tags, {}) : k => tostring(v) if k != "CodeDeploy" },
      { for d in local.deploys : "CodeDeploy:${d.application}" => "true" if d.group == group },
    )
  }
  per_server = { for group, t in local.server_tags : group => [for k, v in t : k if strcontains(v, "{server}")] }
  group_tags = { for group, t in local.server_tags : group => { for k, v in t : k => v if !contains(local.per_server[group], k) } }
  member_tags = {
    for name, s in local.servers : name => {
      for k, v in merge(
        { for k in local.per_server[s.group] : k => local.server_tags[s.group][k] },
        { for k, v in try(local.files[s.group].members[name].tags, {}) : k => tostring(v) },
      ) : k => replace(v, "{server}", name)
    }
  }

  deployment_keys  = ["deployment_group_names", "deployment_config_name", "auto_rollback_configuration"]
  deployment_paths = [for path in fileset(local.config_dir, "**/deployments/*.yml") : path]
  deployment_files = { for path in local.deployment_paths : trimsuffix(basename(path), ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/${path}")), {})) }
  deployment = {
    for app in local.applications : app => {
      groups          = [for g in try(local.deployment_files[app].deployment_group_names, module.ip_plan.codedeploy.groups) : tostring(g)]
      config_name     = tostring(try(local.deployment_files[app].deployment_config_name, module.ip_plan.codedeploy.deployment_config_name))
      rollback_events = [for e in try(local.deployment_files[app].auto_rollback_configuration.events, module.ip_plan.codedeploy.rollback_events) : tostring(e)]
    }
  }
  network = module.ip_plan.networks["${var.environment}/${var.region}"]

  autoscaling_keys = ["min_size", "max_size", "desired_capacity"]
  member_keys      = ["subnet_id", "instance_type", "private_ip", "secondary_private_ips", "tags"]
  volume_keys      = ["device_name", "volume_size", "iops", "throughput", "tags"]
  scaled           = { for group, f in local.files : group => f if can(f.autoscaling_group) }
  fixed            = { for group, f in local.files : group => f if !can(f.autoscaling_group) }
  servers          = module.placement.servers

  own_zone      = try(module.ip_plan.zones[var.environment].private, null)
  private_zones = concat(compact([local.own_zone]), tolist(module.ip_plan.dns.private_zones))

  routes = flatten([for group, f in local.files : [for r in local.rules_of[group] : {
    group         = group
    load_balancer = r.load_balancer
    listener      = r.listener
    listener_arn  = r.listener_arn
    hosts         = try(tolist(r.host_header), [])
    paths         = try(tolist(r.path_pattern), [])
    priority      = r.priority
  }]])
  written = flatten([for group, f in local.files : [for r in try(tolist(f.route53_records), []) : {
    group         = group
    name          = try(tostring(r.name), "?")
    type          = try(tostring(r.type), "?")
    zone          = try(tostring(r.zone_id), null)
    load_balancer = try(tostring(r.alias.name), null)
    evaluate      = try(tobool(r.alias.evaluate_target_health), null)
  }]])
  server_dns = {
    for name, s in local.servers : name => lower(try(local.member_tags[name].DNS, local.group_tags[s.group].DNS))
    if local.own_zone != null && (can(local.member_tags[name].DNS) || can(local.group_tags[s.group].DNS))
  }
  server_names = { for name, label in local.server_dns : name => "${label}.${coalesce(local.own_zone, "?")}" }
  names = [
    for n in local.written : merge(n, {
      by_id   = can(regex(local.zone_id, coalesce(n.zone, "-")))
      private = contains(local.private_zones, coalesce(n.zone, "-"))
      own     = n.zone != null && n.zone == local.own_zone
    })
  ]

  targets              = { for group, f in local.files : group => { for a in try(tolist(f.target_group_attachments), []) : tostring(a.target_group_arn) => tonumber(a.port) if can(tostring(a.target_group_arn)) && can(tonumber(a.port)) } }
  security_group_names = toset([for g in flatten([for f in values(local.files) : try(tolist(f.vpc_security_group_ids), [])]) : g if !startswith(g, "sg-")])

  listener_keys = distinct([for r in local.routes : "${r.load_balancer}:${r.listener}"])
  priorities    = [for r in local.routes : "${r.load_balancer}:${r.listener}:${r.priority}"]
  matches       = flatten([for r in local.routes : [for h in concat(r.hosts, length(r.hosts) == 0 ? ["*"] : []) : [for p in concat(r.paths, length(r.paths) == 0 ? ["*"] : []) : "${r.load_balancer}:${r.listener} ${h}${p == "*" ? "" : p}"]]])

  ami_keys  = ["owners", "filter", "include_deprecated"]
  ami_files = { for path in fileset(local.amis_dir, "*.yml") : trimsuffix(path, ".yml") => yamldecode(file("${local.amis_dir}/${path}")) }
  ami_names = toset([for f in values(local.files) : tostring(f.ami) if can(tostring(f.ami)) && !startswith(try(tostring(f.ami), "ami-"), "ami-")])
  named_image_types = {
    for group, f in local.files : group => distinct(concat([tostring(f.instance_type)], [for s in values(local.servers) : s.type if s.group == group]))
    if can(tostring(f.instance_type)) && contains(local.ami_names, try(tostring(f.ami), ""))
  }
  image_mismatches = local.usable ? flatten([
    for group, types in local.named_image_types : [
      for t in types : "${group}.yml: image ${local.files[group].ami} is ${data.aws_ami.images[local.files[group].ami].architecture}, and ${t} runs ${join(", ", data.aws_ec2_instance_type.types[t].supported_architectures)}"
      if !contains(data.aws_ec2_instance_type.types[t].supported_architectures, data.aws_ami.images[local.files[group].ami].architecture)
    ]
  ]) : []
  ami_pins = { for name, f in local.ami_files : name => [for x in try(tolist(f.filter), []) : try([for v in x.values : tostring(v)], []) if try(x.name, "") == "name"] }

  user_data_paths = { for group, f in local.files : group => "${local.scripts_dir}/${trimprefix(f.user_data, "scripts/")}" if can(f.user_data) }

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a group's name is its file's, so it must be unique" if length(paths) > 1],
    [for group, path in local.user_data_paths : "${group}.yml: user_data is scripts/<name>, a file in the repository's scripts/ folder; ${local.files[group].user_data} is not one" if !startswith(local.files[group].user_data, "scripts/") || !fileexists(path)],
    module.blueprint.problems,
    distinct([for group, ref in local.blueprint_refs : "blueprints/compute/${ref}.yml: role takes ${join(" and ", local.role_keys)}, as the iam stack's roles do; every statement needs effect, actions and resources" if can(local.blueprints[ref].role) && (!alltrue([for k in try(keys(local.blueprints[ref].role), ["?"]) : contains(local.role_keys, k)]) || !alltrue([for st in try(local.blueprints[ref].role.statement, []) : can(st.effect) && can(st.actions) && can(st.resources)]))]),
    [for group, f in local.scaled : "${group}.yml: {server} names one server, and an Auto Scaling group's servers have no names; tag ${join(", ", local.per_server[group])} without them" if length(local.per_server[group]) > 0],
    flatten([for group, f in local.files : [
      for k in concat(keys(try(f.tags, {})), flatten([for m in values(try(f.members, {})) : keys(try(m.tags, {}))])) :
      "${group}.yml: the tag ${k} is the stack's own (Name is the server's, <group>-01); give yours another name" if contains(local.reserved_tags, k)
    ]]),
    [for group, f in local.files : "${group}.yml: vpc_security_group_ids lists ${length(f.vpc_security_group_ids)}; a server takes at most 5" if try(length(f.vpc_security_group_ids) > 5, false)],
    [for group, f in local.files : "${group}.yml: codedeploy is now the CodeDeploy tag: tags: { CodeDeploy: \"['<application>']\" }, and how it rolls out goes in deployments/<application>.yml" if can(f.codedeploy)],
    [for d in local.deploys : "${d.group}.yml: '${d.spec}' in the CodeDeploy tag is not <application> or <application>:Key=Value, with an application of lowercase letters, digits, dots, hyphens and underscores" if !can(regex("^[a-z0-9][a-z0-9._-]{0,99}(:[^=:]+=.+)?$", lower(d.spec)))],
    [for app, selectors in local.application_selectors : "every server running ${app} must give it the same Key=Value selector, or none: ${join(", ", [for s in selectors : "${s.key}=${s.value}"])}" if length(selectors) > 1],
    [for name, f in local.deployment_files : "deployments/${name}.yml: no group's CodeDeploy tag lists ${name}" if !contains(local.applications, name)],
    [for name, f in local.deployment_files : "deployments/${name}.yml: keys are ${join(", ", local.deployment_keys)}" if !alltrue([for k in keys(f) : contains(local.deployment_keys, k)])],
    [for group, f in local.files : "${group}.yml: listener_rules is now listener_rule, one rule: listener_arn, priority, condition.host_header.values and/or condition.path_pattern.values" if can(f.listener_rules)],
    [for r in local.routes : "${r.group}.yml: listener_rule matches at most 5 host names and paths together, AWS's limit for one rule" if length(r.hosts) + length(r.paths) > 5],
    [for group, f in local.files : "${group}.yml: listener_rule needs listener_arn (<load balancer>/<port>, such as services/443), priority, and a condition: host_header.values and/or path_pattern.values" if can(f.listener_rule) && (!can(regex("^[a-z][a-z0-9-]*/[0-9]+$", f.listener_rule.listener_arn)) || !can(f.listener_rule.priority) || !alltrue([for k in try(keys(f.listener_rule.condition), ["?"]) : contains(["host_header", "path_pattern"], k) && can(tolist(f.listener_rule.condition[k].values))]))],
    [for group, f in local.files : "${group}.yml: keys are ${join(", ", local.group_keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.group_keys, k)])],
    flatten([for group, f in local.files : [for name, m in try(f.members, {}) : "${group}.yml: members.${name} takes ${join(", ", local.member_keys)}" if !alltrue([for k in try(keys(m), ["?"]) : contains(local.member_keys, k)])]]),
    [for group, f in local.files : "${group}.yml: ebs_block_device is a list of disks, each with ${join(", ", local.volume_keys)}, and device_name and volume_size required" if can(f.ebs_block_device) && !(can(tolist(f.ebs_block_device)) && alltrue([for v in try(tolist(f.ebs_block_device), []) : can(v.device_name) && can(v.volume_size) && alltrue([for k in try(keys(v), ["?"]) : contains(local.volume_keys, k)])]))],
    flatten([for group, f in local.raw_files : [for token in ["{server}", "{index}"] : "${group}.yml: ${token} fills in a blueprint's value; a file writes the value itself" if strcontains(jsonencode(try(f.tags, {})), token) || strcontains(jsonencode(try(f.members, {})), token)]]),
    [for name in local.ami_names : "ami ${name} is neither an ami- id nor a file in config/amis/ (${name}.yml)" if !contains(keys(local.ami_files), name)],
    [for name, f in local.ami_files : "config/amis/${name}.yml: keys are ${join(", ", local.ami_keys)}, as data.aws_ami takes them; most_recent and name_regex are refused, so an image changes only in a reviewed commit" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.ami_keys, k)])],
    [for name, f in local.ami_files : "config/amis/${name}.yml: owners is a list, such as amazon, self or an account id" if length(try(tolist(f.owners), [])) == 0],
    [for name, pins in local.ami_pins : "config/amis/${name}.yml: filter needs name, with one exact image name and no wildcard, so the image cannot change by itself" if length(pins) != 1 || length(flatten(pins)) != 1 || anytrue([for v in flatten(pins) : strcontains(v, "*") || strcontains(v, "?")])],
    [for group, f in local.files : "${group}.yml: needs ami and instance_type" if !can(f.ami) || !can(f.instance_type)],
    [for group, f in local.files : "${group}.yml: needs iam_instance_profile, a role from the iam stack, so its permissions are chosen" if !can(f.iam_instance_profile)],
    [for group, f in local.files : "${group}.yml: a group's name is 23 characters at most, lowercase letters, digits and hyphens" if !can(regex("^[a-z][a-z0-9-]{0,22}$", group))],
    flatten([for group, f in local.files : [
      for block, allowed in local.block_keys : "${group}.yml: ${block} takes ${join(", ", allowed)}"
      if can(f[block]) && !alltrue([for k in try(keys(f[block]), ["?"]) : contains(allowed, k)])
    ]]),
    [for group, f in local.files : "${group}.yml: target_group.health_check takes ${join(", ", local.health_check_keys)}" if can(f.target_group.health_check) && !alltrue([for k in try(keys(f.target_group.health_check), ["?"]) : contains(local.health_check_keys, k)])],
    [for group, f in local.files : "${group}.yml: target_group.stickiness takes the arguments of aws_lb_target_group's stickiness: ${join(", ", local.stickiness_keys)}, with type lb_cookie or app_cookie" if can(f.target_group.stickiness) && (!alltrue([for k in try(keys(f.target_group.stickiness), ["?"]) : contains(local.stickiness_keys, k)]) || !contains(["lb_cookie", "app_cookie"], try(f.target_group.stickiness.type, "?")))],
    [for group, f in local.files : "${group}.yml: listener_rule needs a target_group with a port to forward to" if length(local.rules_of[group]) > 0 && !can(f.target_group.port)],
    [for group, f in local.files : "${group}.yml: a target_group is reached through a listener_rule; add one, or use target_group_attachments for a load balancer's own target group" if can(f.target_group) && length(local.rules_of[group]) == 0],
    [for group, f in local.files : "${group}.yml: target_group_attachments is a list, each with the arguments of aws_lb_target_group_attachment: target_group_arn (a load balancer stack's target group, <load balancer>-<target>, or its ARN) and port" if can(f.target_group_attachments) && (!can(tolist(f.target_group_attachments)) || !alltrue([for a in try(tolist(f.target_group_attachments), []) : can(keys(a)) && alltrue([for k in keys(a) : contains(local.attachment_keys, k)]) && can(tostring(a.target_group_arn)) && can(tonumber(a.port))]))],
    [for r in local.routes : "${r.group}.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)" if r.priority < 1000],
    [for group, f in local.files : "${group}.yml: route53_records is a list of records, each with the arguments of aws_route53_record: ${join(", ", local.record_keys)}; alias takes name (a load balancer of this environment) and evaluate_target_health" if can(f.route53_records) && (!can(tolist(f.route53_records)) || !alltrue([for r in try(tolist(f.route53_records), []) : can(keys(r)) && alltrue([for k in keys(r) : contains(local.record_keys, k)]) && alltrue([for k in try(keys(r.alias), ["?"]) : contains(["name", "evaluate_target_health"], k)])]))],
    [for n in local.names : "${n.group}.yml: the record ${n.name} needs name, type (A or AAAA), zone_id, alias.name and alias.evaluate_target_health" if n.name == "?" || !contains(["A", "AAAA"], n.type) || n.zone == null || n.load_balancer == null || n.evaluate == null],
    [for p in distinct(local.priorities) : "priority ${split(":", p)[2]} on ${split(":", p)[0]}:${split(":", p)[1]} is used by more than one route" if length([for x in local.priorities : x if x == p]) > 1],
    [for m in distinct(local.matches) : "${m} is claimed by more than one route" if length([for x in local.matches : x if x == m]) > 1],
    [for group, f in local.scaled : "${group}.yml: autoscaling_group replaces count, members and server_name: its instances come and go, so none is named or pinned" if can(f.count) || can(f.members) || can(f.server_name)],
    [for group, f in local.scaled : "${group}.yml: autoscaling_group takes ${join(", ", local.autoscaling_keys)}" if !alltrue([for k in try(keys(f.autoscaling_group), ["?"]) : contains(local.autoscaling_keys, k)])],
    [for group, f in local.scaled : "${group}.yml: autoscaling_policy.target_tracking_configuration takes what aws_autoscaling_policy's does: predefined_metric_specification (predefined_metric_type, resource_label) and target_value" if can(f.autoscaling_policy.target_tracking_configuration) && !(try(alltrue([for k in keys(f.autoscaling_policy.target_tracking_configuration) : contains(["predefined_metric_specification", "target_value"], k)]) && alltrue([for k in keys(f.autoscaling_policy.target_tracking_configuration.predefined_metric_specification) : contains(["predefined_metric_type", "resource_label"], k)]), false) && can(tostring(f.autoscaling_policy.target_tracking_configuration.predefined_metric_specification.predefined_metric_type)) && can(tonumber(f.autoscaling_policy.target_tracking_configuration.target_value)))],
    [for group, f in local.scaled : "${group}.yml: autoscaling_group needs min_size <= desired_capacity <= max_size" if !try(f.autoscaling_group.min_size <= f.autoscaling_group.desired_capacity && f.autoscaling_group.desired_capacity <= f.autoscaling_group.max_size, false)],
    [for group, f in local.scaled : "${group}.yml: ${var.environment}'s VPC in ${var.region} has no ${try(f.tier, "private")} tier" if !contains(keys(local.network.subnets), try(f.tier, "private"))],
    module.placement.problems,
    [for n in local.names : "${n.group}.yml: ${n.name} is in ${n.zone}, which is not a private zone nor one of dns.public_domain in config/global.yml" if n.zone != null && !n.by_id && !n.private && !contains(module.ip_plan.dns.public_domains, coalesce(n.zone, "?"))],
    [for n in local.names : "${n.group}.yml: ${n.name} is not in its zone_id ${n.zone}; name is the record's full name" if n.zone != null && !n.by_id && !endswith(n.name, ".${coalesce(n.zone, "?")}")],
    flatten([for r in local.routes : [for h in r.hosts : "${r.group}.yml: host_header ${h} is a full host name, lowercase, such as ${lower(replace(h, " ", "-"))}-${var.environment}.<domain>: names are never filled in" if !strcontains(h, ".") || !can(regex("^(\\*\\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", h))]]),
    flatten([for r in local.routes : [for p in r.paths : "${r.group}.yml: path_pattern ${p} starts with /, such as /${r.group}/*" if !can(regex("^/[A-Za-z0-9._~*?/{}-]*$", p))]]),
    [for name in distinct([for n in local.names : n.name]) : "${name} is named by more than one group's route or record" if length([for n in local.names : n if n.name == name]) > 1],
    [for name, label in local.server_dns : "${local.servers[name].group}.yml: DNS ${label} on ${name} is one name, lowercase letters, digits and hyphens: ${name}'s address in ${local.own_zone}" if !can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", label))],
    [for full in distinct(concat(values(local.server_names), [for n in local.names : n.name])) : "${full} is the DNS tag of more than one server, or of a server and a record: ${join(", ", concat([for name, f in local.server_names : name if f == full], [for n in local.names : "${n.group}.yml" if n.name == full]))}" if length([for f in values(local.server_names) : f if f == full]) + length([for n in local.names : n if n.name == full]) > 1 && length([for f in values(local.server_names) : f if f == full]) > 0],
  )
  usable = length(local.problems) == 0
}
