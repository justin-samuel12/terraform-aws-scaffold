locals {
  config_dir = coalesce(var.config_dir, path.root)
  raw_files  = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }

  # Blueprints -- docs/blueprints.md. A file saying blueprint: <name>/v<n> is a group whose settings come from
  # blueprints/<name>/v<n>.yml, with {app}, {environment}, {region} and any required value filled in, and only the keys the
  # blueprint allows set by the file. It becomes an ordinary group here, so everything below applies to it unchanged.
  blueprints_dir = abspath(coalesce(var.blueprints_dir, "${var.config_path == null ? "${path.root}/../../../../config" : var.config_path}/../blueprints"))
  blueprint_refs = { for group, f in local.raw_files : group => tostring(f.blueprint) if can(f.blueprint) }
  blueprints = {
    for ref in distinct(values(local.blueprint_refs)) : ref => try(yamldecode(file("${local.blueprints_dir}/${ref}.yml")), null)
  }
  # Every key path a file sets, to three levels (target_group.health_check.path), to check against what its blueprint allows.
  blueprint_paths = {
    for group, ref in local.blueprint_refs : group => flatten([
      for k, v in local.raw_files[group] : can(keys(v)) ? flatten([
        for k2, v2 in v : can(keys(v2)) ? [for k3, v3 in v2 : "${k}.${k2}.${k3}"] : ["${k}.${k2}"]
      ]) : [k] if k != "blueprint"
    ])
  }
  # The blueprint's group, its placeholders filled in, then the file's own values: maps merged two levels deep, so a file can
  # change one health check setting without restating the target group.
  blueprint_groups = {
    for group, ref in local.blueprint_refs : group => try(yamldecode(replace(replace(replace(replace(
      yamlencode(local.blueprints[ref].group),
      "\"{priority}\"", tostring(try(tonumber(local.raw_files[group].priority), 0))),
      "{app}", group), "{environment}", var.environment), "{region}", var.region
    )), {})
  }
  expanded = {
    for group, ref in local.blueprint_refs : group => merge(
      local.blueprint_groups[group],
      {
        for k, v in local.raw_files[group] : k => try(merge(local.blueprint_groups[group][k], {
          for k2 in keys(v) : k2 => try(merge(local.blueprint_groups[group][k][k2], { for k3 in keys(v[k2]) : k3 => v[k2][k3] }), v[k2])
        }), v) if !contains(concat(["blueprint"], try(local.blueprints[ref].requires, [])), k)
      },
      # The role is the application's own, made here from the blueprint's permissions -- see the app_roles module.
      can(local.blueprints[ref].role) ? { iam_instance_profile = local.app_role_names[group] } : {},
      # A blueprint's boot script sits beside it, in blueprints/<name>/.
      can(local.blueprint_groups[group].user_data) ? { user_data = "${local.blueprints_dir}/${split("/", ref)[0]}/${local.blueprint_groups[group].user_data}" } : {},
    )
  }
  files = merge(local.raw_files, local.expanded)

  # A role per application built from a blueprint: the same permissions as every other app on it, its own identity (so Vault's
  # AWS auth, which knows a server by its role, tells applications apart). Roles are global, so the name carries the region.
  app_role_names    = { for group, ref in local.blueprint_refs : group => "${var.environment}-${group}-${var.region}" if can(local.blueprints[ref].role) }
  app_role_policies = toset(flatten([for group, ref in local.blueprint_refs : try(local.blueprints[ref].role.policies, []) if contains(keys(local.app_role_names), group)]))
  # A group of servers: what they share and how many, then one block per optional feature, each named after its AWS resource.
  server_keys  = ["count", "instance_type", "ami", "tier", "iam_instance_profile", "security_groups", "root_block_device", "ebs_block_device", "backup", "user_data", "members", "tags"]
  feature_keys = ["autoscaling", "target_group", "listener_rules", "target_group_attachments", "route53_records"]
  group_keys   = concat(local.server_keys, local.feature_keys)
  block_keys = {
    target_group = ["port", "protocol", "slow_start", "health_check", "stickiness"]
  }

  # CodeDeploy: a group's servers say which applications they run in their CodeDeploy tag, a list such as
  # "['orders-api', 'reports:Function=worker']" (an application, and optionally a Key=Value every server running it must
  # carry). Each becomes a tag CodeDeploy:<application> on the servers, and each application, the same name in every
  # environment, gets its deployment groups here -- docs/compute.md#deploying-with-codedeploy.
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
  # Shared between environments when every server running it is containerized (the isContainerized tag).
  containerized = { for app, groups in local.application_groups : app => alltrue([for g in groups : lower(trimspace(try(tostring(local.files[g].tags.isContainerized), ""))) == "true"]) }

  # The servers' own tags: CodeDeploy becomes one CodeDeploy:<application> tag per application it lists.
  server_tags = {
    for group, f in local.files : group => merge(
      { for k, v in try(f.tags, {}) : k => tostring(v) if k != "CodeDeploy" },
      { for d in local.deploys : "CodeDeploy:${d.application}" => "true" if d.group == group },
    )
  }

  # How each application deploys: the defaults in config/global.yml (codedeploy:), and anything an application's own
  # deployments/<application>.yml beside the server files says instead.
  deployment_keys  = ["deployment_group_names", "deployment_config_name", "auto_rollback_configuration"]
  deployment_files = { for name in fileset("${local.config_dir}/deployments", "*.yml") : trimsuffix(name, ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/deployments/${name}")), {})) }
  deployment = {
    for app in local.applications : app => {
      groups          = [for g in try(local.deployment_files[app].deployment_group_names, module.ip_plan.codedeploy.groups) : tostring(g)]
      config_name     = tostring(try(local.deployment_files[app].deployment_config_name, module.ip_plan.codedeploy.deployment_config_name))
      rollback_events = [for e in try(local.deployment_files[app].auto_rollback_configuration.events, module.ip_plan.codedeploy.rollback_events) : tostring(e)]
    }
  }
  network = module.ip_plan.networks["${var.environment}/${var.region}"]

  # Groups with autoscaling are an Auto Scaling group across their tier; every other group is fixed, named servers.
  autoscaling_keys = ["min_size", "max_size", "desired_capacity", "target_tracking_configuration"]
  scaled           = { for group, f in local.files : group => f if can(f.autoscaling) }
  fixed            = { for group, f in local.files : group => f if !can(f.autoscaling) }
  servers          = module.placement.servers

  # Every route and name, flattened, so they can be checked across groups and looked up once.
  routes = flatten([for group, f in local.files : [for r in try(f.listener_rules, []) : {
    group         = group
    load_balancer = r.load_balancer
    listener      = tostring(try(r.listener, 443))
    hosts         = try(tolist(r.host_header), [])
    paths         = try(tolist(r.path_pattern), [])
    priority      = r.priority
  }]])
  names = flatten([for group, f in local.files : [for n in try(f.route53_records, []) : {
    group         = group
    name          = "${n.name}.${n.zone}"
    zone          = n.zone
    private       = try(n.private_zone, false)
    load_balancer = try(n.load_balancer, f.listener_rules[0].load_balancer, split("/", keys(f.target_group_attachments)[0])[0], null)
  }]])

  targets = { for group, f in local.files : group => { for t, port in try(f.target_group_attachments, {}) : t => port } }

  listener_keys = distinct([for r in local.routes : "${r.load_balancer}:${r.listener}"])
  priorities    = [for r in local.routes : "${r.load_balancer}:${r.listener}:${r.priority}"]
  matches       = flatten([for r in local.routes : [for h in concat(r.hosts, length(r.hosts) == 0 ? ["*"] : []) : [for p in concat(r.paths, length(r.paths) == 0 ? ["*"] : []) : "${r.load_balancer}:${r.listener} ${h}${p == "*" ? "" : p}"]]])

  # A boot script is read from beside the group's file (or a blueprint's); one that is missing stops the plan, never builds
  # servers without it.
  user_data_paths = { for group, f in local.files : group => (startswith(f.user_data, "/") ? f.user_data : "${local.config_dir}/${f.user_data}") if can(f.user_data) }

  problems = concat(
    [for group, path in local.user_data_paths : "${group}.yml: user_data ${local.files[group].user_data} is not there; it is read from beside the file" if !fileexists(path)],
    [for group, ref in local.blueprint_refs : "${group}.yml: blueprint ${ref} is <name>/v<number>, such as backend-service/v1" if !can(regex("^[a-z0-9][a-z0-9-]*/v[0-9]+$", ref))],
    [for group, ref in local.blueprint_refs : "${group}.yml: blueprint ${ref} not found: blueprints/${split("/", ref)[0]}/ has ${join(", ", [for v in fileset("${local.blueprints_dir}/${split("/", ref)[0]}", "v*.yml") : trimsuffix(v, ".yml")]) == "" ? "nothing" : join(", ", [for v in fileset("${local.blueprints_dir}/${split("/", ref)[0]}", "v*.yml") : trimsuffix(v, ".yml")])}" if can(regex("^[a-z0-9][a-z0-9-]*/v[0-9]+$", ref)) && local.blueprints[ref] == null],
    [for group, ref in local.blueprint_refs : "blueprints/${ref}.yml: it needs a group: the settings every app on it gets" if local.blueprints[ref] != null && !can(keys(local.blueprints[ref].group))],
    flatten([for group, paths in local.blueprint_paths : [
      for p in paths : "${group}.yml: ${p} is set by blueprint ${local.blueprint_refs[group]}; an app on it may set ${join(", ", try(local.blueprints[local.blueprint_refs[group]].allows, []))}"
      if !contains(try(local.blueprints[local.blueprint_refs[group]].requires, []), split(".", p)[0]) && !anytrue([for a in try(local.blueprints[local.blueprint_refs[group]].allows, []) : p == a || startswith(p, "${a}.")])
    ] if local.blueprints[local.blueprint_refs[group]] != null]),
    flatten([for group, ref in local.blueprint_refs : [
      for r in try(local.blueprints[ref].requires, []) : "${group}.yml: blueprint ${ref} needs ${r}" if !can(local.raw_files[group][r])
    ] if local.blueprints[ref] != null]),
    [for group, ref in local.blueprint_refs : "${group}.yml: instance_type ${try(local.raw_files[group].instance_type, "")} is not one blueprint ${ref} offers: ${join(", ", try(local.blueprints[ref].instance_types, []))}" if can(local.raw_files[group].instance_type) && can(local.blueprints[ref].instance_types) && !contains(try(local.blueprints[ref].instance_types, []), try(local.raw_files[group].instance_type, ""))],
    [for group, f in local.files : "${group}.yml: codedeploy is now the CodeDeploy tag: tags: { CodeDeploy: \"['<application>']\" }, and how it rolls out goes in deployments/<application>.yml" if can(f.codedeploy)],
    [for d in local.deploys : "${d.group}.yml: '${d.spec}' in the CodeDeploy tag is not <application> or <application>:Key=Value, with an application of lowercase letters, digits, dots, hyphens and underscores" if !can(regex("^[a-z0-9][a-z0-9._-]{0,99}(:[^=:]+=.+)?$", lower(d.spec)))],
    [for app, selectors in local.application_selectors : "every server running ${app} must give it the same Key=Value selector, or none: ${join(", ", [for s in selectors : "${s.key}=${s.value}"])}" if length(selectors) > 1],
    [for name, f in local.deployment_files : "deployments/${name}.yml: no group's CodeDeploy tag lists ${name}" if !contains(local.applications, name)],
    [for name, f in local.deployment_files : "deployments/${name}.yml: keys are ${join(", ", local.deployment_keys)}" if !alltrue([for k in keys(f) : contains(local.deployment_keys, k)])],
    [for group, f in local.files : "${group}.yml: keys are ${join(", ", local.group_keys)}" if !alltrue([for k in try(keys(f), []) : contains(local.group_keys, k)])],
    [for group, f in local.files : "${group}.yml: needs ami and instance_type" if !can(f.ami) || !can(f.instance_type)],
    [for group, f in local.files : "${group}.yml: needs iam_instance_profile, a role from the iam stack, so its permissions are chosen" if !can(f.iam_instance_profile)],
    [for group, f in local.files : "${group}.yml: a group's name is 23 characters at most, lowercase letters, digits and hyphens" if !can(regex("^[a-z][a-z0-9-]{0,22}$", group))],
    flatten([for group, f in local.files : [
      for block, allowed in local.block_keys : "${group}.yml: ${block} takes ${join(", ", allowed)}"
      if can(f[block]) && !alltrue([for k in try(keys(f[block]), ["?"]) : contains(allowed, k)])
    ]]),
    [for group, f in local.files : "${group}.yml: listener_rules need a target_group with a port to forward to" if length(try(f.listener_rules, [])) > 0 && !can(f.target_group.port)],
    [for group, f in local.files : "${group}.yml: a target_group is reached through listener_rules; add them, or use target_group_attachments for a load balancer's own target group" if can(f.target_group) && length(try(f.listener_rules, [])) == 0],
    [for group, f in local.files : "${group}.yml: target_group_attachments are <load balancer>/<target>: <port>" if !alltrue([for t, port in try(f.target_group_attachments, {}) : can(regex("^[a-z0-9-]+/[a-z0-9-]+$", t)) && can(tonumber(port))])],
    [for r in local.routes : "${r.group}.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)" if r.priority < 1000],
    [for group, f in local.files : "${group}.yml: route53_records need a load balancer: from listener_rules, target_group_attachments, or load_balancer on the record" if length([for n in local.names : n if n.group == group && n.load_balancer == null]) > 0],
    [for p in distinct(local.priorities) : "priority ${split(":", p)[2]} on ${split(":", p)[0]}:${split(":", p)[1]} is used by more than one route" if length([for x in local.priorities : x if x == p]) > 1],
    [for m in distinct(local.matches) : "${m} is claimed by more than one route" if length([for x in local.matches : x if x == m]) > 1],
    [for group, f in local.scaled : "${group}.yml: autoscaling replaces count and members: its instances come and go, so none is named or pinned" if can(f.count) || can(f.members)],
    [for group, f in local.scaled : "${group}.yml: autoscaling takes ${join(", ", local.autoscaling_keys)}" if !alltrue([for k in try(keys(f.autoscaling), ["?"]) : contains(local.autoscaling_keys, k)])],
    [for group, f in local.scaled : "${group}.yml: autoscaling needs min_size <= desired_capacity <= max_size" if !try(f.autoscaling.min_size <= f.autoscaling.desired_capacity && f.autoscaling.desired_capacity <= f.autoscaling.max_size, false)],
    [for group, f in local.scaled : "${group}.yml: ${var.environment}'s VPC in ${var.region} has no ${try(f.tier, "private")} tier" if !contains(keys(local.network.subnets), try(f.tier, "private"))],
    module.placement.problems,
  )
  usable = length(local.problems) == 0
}
