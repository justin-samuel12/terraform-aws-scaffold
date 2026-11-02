locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  # A group of servers: what they share and how many, then one block per optional feature, each named after its AWS resource.
  server_keys  = ["count", "instance_type", "ami", "tier", "iam_instance_profile", "security_groups", "root_block_device", "ebs_block_device", "backup", "user_data", "members", "tags"]
  feature_keys = ["autoscaling", "target_group", "listener_rules", "target_group_attachments", "codedeploy", "route53_records"]
  group_keys   = concat(local.server_keys, local.feature_keys)
  block_keys = {
    target_group = ["port", "protocol", "slow_start", "health_check", "stickiness"]
    codedeploy   = ["deployment_config_name"]
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

  problems = concat(
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
    [for group, f in local.files : "${group}.yml: codedeploy needs deployment_config_name" if can(f.codedeploy) && !can(f.codedeploy.deployment_config_name)],
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
