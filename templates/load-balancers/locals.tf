locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  files = { for name, paths in local.found : name => yamldecode(file("${local.config_dir}/${sort(paths)[0]}")) }

  file_keys                 = ["load_balancer_type", "internal", "subnets", "security_groups", "listeners", "target_groups", "listener_rules", "listener_certificates"]
  list_keys                 = ["subnets", "security_groups", "listeners", "listener_certificates"]
  map_keys                  = ["target_groups", "listener_rules"]
  listener_keys             = ["port", "protocol", "certificate_arn", "default_action"]
  action_keys               = ["type", "target_group_arn", "redirect", "fixed_response"]
  redirect_keys             = ["host", "path", "port", "protocol", "query", "status_code"]
  fixed_response_keys       = ["content_type", "message_body", "status_code"]
  target_group_keys         = ["port", "protocol", "target_type", "deregistration_delay", "health_check"]
  health_check_keys         = ["enabled", "path", "port", "protocol", "matcher", "interval", "timeout", "healthy_threshold", "unhealthy_threshold"]
  rule_keys                 = ["listener_arn", "priority", "action", "condition"]
  condition_keys            = ["host_header", "path_pattern"]
  listener_certificate_keys = ["listener_arn", "certificate_arn"]

  subnet_names = sort(flatten([for tier, cidrs in local.network.subnets : [for zone in local.network.zones : "${tier}-${split("-", zone)[1]}"]]))

  lists = {
    for name, f in local.files : name => {
      for key in local.list_keys : key => try([for x in f[key] : x if !can(keys(f[key]))], [])
    }
  }
  maps = {
    for name, f in local.files : name => {
      for key in local.map_keys : key => try({ for k, v in f[key] : k => v if can(keys(f[key])) }, {})
    }
  }

  raw_actions = merge(
    merge([for name, f in local.files : {
      for i, l in local.lists[name].listeners : "${name}/listeners/${i}" => { owner = name, label = "the listener on port ${try(tostring(l.port), "?")}", block = "default_action", value = try(l.default_action, null) }
    }]...),
    merge([for name, f in local.files : {
      for rule, r in local.maps[name].listener_rules : "${name}/listener_rules/${rule}" => { owner = name, label = "the listener rule ${rule}", block = "action", value = try(r.action, null) }
    }]...),
  )
  actions = {
    for key, a in local.raw_actions : key => {
      type             = try(tostring(a.value.type), "")
      target_group_arn = try(tostring(a.value.target_group_arn), null)
      redirect = try(a.value.redirect, null) == null ? null : {
        host        = try(tostring(a.value.redirect.host), null)
        path        = try(tostring(a.value.redirect.path), null)
        port        = try(tostring(a.value.redirect.port), null)
        protocol    = try(tostring(a.value.redirect.protocol), null)
        query       = try(tostring(a.value.redirect.query), null)
        status_code = try(tostring(a.value.redirect.status_code), "")
      }
      fixed_response = try(a.value.fixed_response, null) == null ? null : {
        content_type = try(tostring(a.value.fixed_response.content_type), "")
        message_body = try(tostring(a.value.fixed_response.message_body), null)
        status_code  = try(tostring(a.value.fixed_response.status_code), null)
      }
    }
  }

  load_balancers = {
    for name, f in local.files : name => {
      load_balancer_type = try(tostring(f.load_balancer_type), "")
      internal           = try(tobool(f.internal), null)
      subnets            = [for s in local.lists[name].subnets : try(tostring(s), "")]
      security_groups    = [for g in local.lists[name].security_groups : try(tostring(g), "")]
      listeners = [
        for i, l in local.lists[name].listeners : {
          port            = try(tonumber(l.port), 0)
          protocol        = try(tostring(l.protocol), "")
          certificate_arn = try(tostring(l.certificate_arn), null)
          default_action  = local.actions["${name}/listeners/${i}"]
        }
      ]
      target_groups = {
        for target, t in local.maps[name].target_groups : target => {
          port                 = try(tonumber(t.port), 0)
          protocol             = try(tostring(t.protocol), "")
          target_type          = try(tostring(t.target_type), "")
          deregistration_delay = try(tonumber(t.deregistration_delay), -1)
          health_check = try(t.health_check, null) == null ? null : {
            enabled             = try(tobool(t.health_check.enabled), null)
            path                = try(tostring(t.health_check.path), null)
            port                = try(tostring(t.health_check.port), null)
            protocol            = try(tostring(t.health_check.protocol), null)
            matcher             = try(tostring(t.health_check.matcher), null)
            interval            = try(tonumber(t.health_check.interval), null)
            timeout             = try(tonumber(t.health_check.timeout), null)
            healthy_threshold   = try(tonumber(t.health_check.healthy_threshold), null)
            unhealthy_threshold = try(tonumber(t.health_check.unhealthy_threshold), null)
          }
        }
      }
      listener_rules = {
        for rule, r in local.maps[name].listener_rules : rule => {
          listener_arn = try(tostring(r.listener_arn), "")
          priority     = try(tonumber(r.priority), 0)
          action       = local.actions["${name}/listener_rules/${rule}"]
          condition = {
            for key in local.condition_keys : key => try(r.condition[key], null) == null ? null : { values = try([for v in r.condition[key].values : tostring(v)], []) }
          }
        }
      }
      listener_certificates = [
        for c in local.lists[name].listener_certificates : {
          listener_arn    = try(tostring(c.listener_arn), "")
          certificate_arn = try(tostring(c.certificate_arn), "")
        }
      ]
    }
  }

  ports = { for name, lb in local.load_balancers : name => [for l in lb.listeners : tostring(l.port)] }

  subnet_lookups = toset(flatten([for lb in local.load_balancers : [for s in lb.subnets : s if contains(local.subnet_names, s)]]))
  group_lookups  = toset(flatten([for lb in local.load_balancers : [for g in lb.security_groups : g if g != "" && !startswith(g, "sg-")]]))
  certificate_lookups = toset(flatten([for lb in local.load_balancers : concat(
    [for l in lb.listeners : l.certificate_arn if l.certificate_arn != null && !startswith(coalesce(l.certificate_arn, "arn:"), "arn:")],
    [for c in lb.listener_certificates : c.certificate_arn if c.certificate_arn != "" && !startswith(c.certificate_arn, "arn:")],
  )]))

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a load balancer's name is its file's, so it must be unique" if length(paths) > 1],
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}: aws_lb's load_balancer_type, internal, subnets and security_groups, then its aws_lb_listener, aws_lb_target_group, aws_lb_listener_rule and aws_lb_listener_certificate resources" if !can(keys(f)) || !alltrue([for k in try(keys(f), []) : contains(local.file_keys, k)])],
    [for name, f in local.files : "${name}.yml: ${join(", ", local.list_keys)} are lists, and ${join(", ", local.map_keys)} maps by name" if anytrue(concat([for k in local.list_keys : try(f[k], null) != null && (can(keys(f[k])) || !can([for x in f[k] : x]))], [for k in local.map_keys : try(f[k], null) != null && !can(keys(f[k]))]))],
    [for name, lb in local.load_balancers : "${name}.yml: load_balancer_type is application or network" if !contains(["application", "network"], lb.load_balancer_type)],
    [for name, lb in local.load_balancers : "${name}.yml: internal is true or false" if lb.internal == null],
    [for name, lb in local.load_balancers : "${name}.yml: subnets lists at least two subnets" if length(lb.subnets) < 2],
    flatten([for name, lb in local.load_balancers : [
      for s in lb.subnets : "${name}.yml: subnets: ${s} is not a subnet of the ${var.environment} VPC in ${var.region} (${join(", ", local.subnet_names)}), nor a subnet ID" if !startswith(s, "subnet-") && !contains(local.subnet_names, s)
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for i, l in local.lists[name].listeners : "${name}.yml: a listener takes the arguments of aws_lb_listener: ${join(", ", local.listener_keys)} (ssl_policy is fixed)" if !can(keys(l)) || !alltrue([for k in try(keys(l), []) : contains(local.listener_keys, k)])
    ]]),
    [for name, lb in local.load_balancers : "${name}.yml: each listener has its own port" if length(distinct(local.ports[name])) != length(local.ports[name])],
    [for key, a in local.raw_actions : "${a.owner}.yml: ${a.label} needs ${a.block}" if a.value == null],
    [for key, a in local.raw_actions : "${a.owner}.yml: ${a.block} of ${a.label} takes ${join(", ", local.action_keys)}" if a.value != null && (!can(keys(a.value)) || !alltrue([for k in try(keys(a.value), []) : contains(local.action_keys, k)]))],
    [for key, a in local.raw_actions : "${a.owner}.yml: redirect in ${a.label} takes ${join(", ", local.redirect_keys)}" if try(a.value.redirect, null) != null && (!can(keys(a.value.redirect)) || !alltrue([for k in try(keys(a.value.redirect), []) : contains(local.redirect_keys, k)]))],
    [for key, a in local.raw_actions : "${a.owner}.yml: fixed_response in ${a.label} takes ${join(", ", local.fixed_response_keys)}" if try(a.value.fixed_response, null) != null && (!can(keys(a.value.fixed_response)) || !alltrue([for k in try(keys(a.value.fixed_response), []) : contains(local.fixed_response_keys, k)]))],
    [for key, a in local.actions : "${local.raw_actions[key].owner}.yml: target_group_arn ${a.target_group_arn} in ${local.raw_actions[key].label} is not a target group in this file, nor an ARN" if a.target_group_arn != null && !startswith(coalesce(a.target_group_arn, "arn:"), "arn:") && !contains(keys(local.maps[local.raw_actions[key].owner].target_groups), coalesce(a.target_group_arn, "-"))],
    flatten([for name, lb in local.load_balancers : [
      for target, t in local.maps[name].target_groups : "${name}.yml: the target group ${target} takes the arguments of aws_lb_target_group: ${join(", ", local.target_group_keys)}" if !can(keys(t)) || !alltrue([for k in try(keys(t), []) : contains(local.target_group_keys, k)])
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for target, t in lb.target_groups : "${name}.yml: the target group ${target} needs port, protocol, target_type and deregistration_delay" if t.port == 0 || t.protocol == "" || t.target_type == "" || t.deregistration_delay < 0
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for target, t in local.maps[name].target_groups : "${name}.yml: health_check in the target group ${target} takes ${join(", ", local.health_check_keys)}" if try(t.health_check, null) != null && (!can(keys(t.health_check)) || !alltrue([for k in try(keys(t.health_check), []) : contains(local.health_check_keys, k)]))
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for rule, r in local.maps[name].listener_rules : "${name}.yml: the listener rule ${rule} takes the arguments of aws_lb_listener_rule: ${join(", ", local.rule_keys)}" if !can(keys(r)) || !alltrue([for k in try(keys(r), []) : contains(local.rule_keys, k)])
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for rule, r in local.maps[name].listener_rules : "${name}.yml: condition in the listener rule ${rule} takes host_header and path_pattern, each with values" if !can(keys(r.condition)) || !alltrue([for k in try(keys(r.condition), []) : contains(local.condition_keys, k) && can(keys(r.condition[k])) && try(jsonencode(keys(r.condition[k])) == jsonencode(["values"]), false)])
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for rule, r in lb.listener_rules : "${name}.yml: listener_arn ${r.listener_arn} of the listener rule ${rule} is not a listener port in this file, nor an ARN" if !startswith(r.listener_arn, "arn:") && !contains(local.ports[name], r.listener_arn)
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for c in local.lists[name].listener_certificates : "${name}.yml: a listener certificate takes the arguments of aws_lb_listener_certificate: ${join(", ", local.listener_certificate_keys)}" if !can(keys(c)) || !alltrue([for k in try(keys(c), []) : contains(local.listener_certificate_keys, k)])
    ]]),
    flatten([for name, lb in local.load_balancers : [
      for c in lb.listener_certificates : "${name}.yml: listener_arn ${c.listener_arn} of a listener certificate is not a listener port in this file" if !contains(local.ports[name], c.listener_arn)
    ]]),
  )

  resolved = {
    for name, lb in local.load_balancers : name => merge(lb, {
      subnets         = [for s in lb.subnets : startswith(s, "subnet-") ? s : try(data.aws_subnet.subnets[s].id, s)]
      security_groups = [for g in lb.security_groups : startswith(g, "sg-") ? g : try(data.aws_security_group.groups[g].id, g)]
      listeners = [
        for l in lb.listeners : merge(l, {
          certificate_arn = l.certificate_arn == null ? null : startswith(l.certificate_arn, "arn:") ? l.certificate_arn : try(data.aws_acm_certificate.certificates[l.certificate_arn].arn, null)
        })
      ]
      listener_certificates = {
        for key, c in { for c in lb.listener_certificates : "${c.listener_arn} ${c.certificate_arn}" => c... } : key => {
          listener_arn    = c[0].listener_arn
          certificate_arn = startswith(c[0].certificate_arn, "arn:") ? c[0].certificate_arn : try(data.aws_acm_certificate.certificates[c[0].certificate_arn].arn, "")
        }
      }
    })
  }
}
