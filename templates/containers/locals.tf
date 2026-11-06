locals {
  config_dir = coalesce(var.config_dir, "${path.root}/config")
  found = {
    for path in fileset(local.config_dir, "**/*.yml") : trimsuffix(basename(path), ".yml") => path...
  }
  raw_files      = { for name, paths in local.found : name => merge({}, try(yamldecode(file("${local.config_dir}/${sort(paths)[0]}")), {})) }
  blueprints_dir = abspath(coalesce(var.blueprints_dir, "${var.config_path == null ? "${path.root}/../../../../config" : var.config_path}/../blueprints/containers"))
  files          = module.blueprint.files
  network        = module.ip_plan.networks["${var.environment}/${var.region}"]

  file_keys = [
    "cpu", "memory", "desired_count", "network_configuration", "runtime_platform", "capacity_provider_strategy", "enable_execute_command",
    "container_definitions", "deployment_minimum_healthy_percent", "deployment_maximum_percent", "deployment_controller", "deployment_group",
    "target_group", "listener_rule", "appautoscaling_target", "appautoscaling_policy", "statement", "tags",
  ]
  block_keys = {
    network_configuration = ["subnets", "security_groups"]
    runtime_platform      = ["cpu_architecture", "operating_system_family"]
    deployment_controller = ["type"]
    deployment_group      = ["deployment_config_name", "blue_green_deployment_config"]
    target_group          = ["health_check"]
    appautoscaling_target = ["min_capacity", "max_capacity"]
    appautoscaling_policy = ["target_tracking_scaling_policy_configuration"]
  }
  health_keys        = ["path", "matcher", "interval", "timeout", "healthy_threshold", "unhealthy_threshold"]
  definition_keys    = ["name", "image", "essential", "command", "portMappings", "environment", "secrets", "healthCheck"]
  container_hc_keys  = ["command", "interval", "timeout", "retries", "startPeriod"]
  statement_keys     = ["effect", "actions", "resources", "condition"]
  rule_keys          = ["listener_arn", "priority", "condition"]
  controllers        = ["ECS", "CODE_DEPLOY"]
  secret_name        = "(?i)(password|secret|token|private_key|api_key|credential)"
  secret_arn         = "^arn:aws[a-z-]*:(secretsmanager|ssm):[a-z0-9-]+:[0-9]{12}:(secret:|parameter/)"
  fargate_cpu        = [256, 512, 1024, 2048, 4096, 8192, 16384]
  fargate_metrics    = ["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization", "ALBRequestCountPerTarget"]
  ecs_config_pattern = "^CodeDeployDefault\\.ECS"

  definitions = { for name, f in local.files : name => try([for c in f.container_definitions : c], []) }
  containers = {
    for name, cs in local.definitions : name => [
      for c in cs : {
        name         = try(tostring(c.name), "?")
        image        = try(tostring(c.image), "")
        essential    = try(tobool(c.essential), null)
        command      = try([for x in c.command : tostring(x)], null)
        portMappings = [for p in try(c.portMappings, []) : { containerPort = try(tonumber(p.containerPort), null) }]
        environment  = [for e in try(c.environment, []) : { name = try(tostring(e.name), "?"), value = try(tostring(e.value), "") }]
        secrets      = [for s in try(c.secrets, []) : { name = try(tostring(s.name), "?"), valueFrom = try(tostring(s.valueFrom), "") }]
        healthCheck = can(c.healthCheck.command) ? {
          command     = [for x in c.healthCheck.command : tostring(x)]
          interval    = try(tonumber(c.healthCheck.interval), null)
          timeout     = try(tonumber(c.healthCheck.timeout), null)
          retries     = try(tonumber(c.healthCheck.retries), null)
          startPeriod = try(tonumber(c.healthCheck.startPeriod), null)
        } : null
      }
    ]
  }
  ported     = { for name, cs in local.containers : name => [for c in cs : c if length(c.portMappings) > 0] }
  controller = { for name, f in local.files : name => try(tostring(f.deployment_controller.type), "ECS") }
  blue_green = toset([for name, c in local.controller : name if c == "CODE_DEPLOY"])

  subnet_names    = { for name, f in local.files : name => try([for s in f.network_configuration.subnets : tostring(s)], []) }
  group_names     = { for name, f in local.files : name => try([for g in f.network_configuration.security_groups : tostring(g)], []) }
  known_subnets   = flatten([for tier, cidrs in local.network.subnets : [for i, c in cidrs : "${tier}-az${i + 1}"]])
  scaling         = { for name, f in local.files : name => try(f.appautoscaling_policy.target_tracking_scaling_policy_configuration, null) }
  scaling_metrics = { for name, s in local.scaling : name => try(tostring(s.predefined_metric_specification.predefined_metric_type), "") }

  routes = flatten([for name, f in local.files : [for r in can(f.listener_rule) ? [f.listener_rule] : [] : {
    service       = name
    load_balancer = try(split("/", tostring(r.listener_arn))[0], "?")
    listener      = try(split("/", tostring(r.listener_arn))[1], "?")
    listener_arn  = try(tostring(r.listener_arn), "")
    hosts         = try([for h in r.condition.host_header.values : tostring(h)], [])
    paths         = try([for p in r.condition.path_pattern.values : tostring(p)], [])
    priority      = try(tonumber(r.priority), 0)
    keys          = try(keys(r), ["?"])
    conditions    = try(keys(r.condition), [])
  }]])
  listener_keys = distinct([for r in local.routes : "${r.load_balancer}:${r.listener}"])
  priorities    = [for r in local.routes : "${r.load_balancer}:${r.listener}:${r.priority}"]

  problems = concat(
    [for name, paths in local.found : "${name}.yml is in more than one folder (${join(", ", sort(paths))}); a service's name is its file's, so it must be unique" if length(paths) > 1],
    module.blueprint.problems,
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}, as aws_ecs_service and aws_ecs_task_definition take them" if length(f) == 0 || !alltrue([for k in keys(f) : contains(local.file_keys, k)])],
    flatten([for name, f in local.files : [for k in keys(try(f.tags, {})) : "${name}.yml: the tag ${k} is the stack's own; give yours another name" if contains(["Name", "Service"], k)]]),
    [for name in keys(local.files) : "${name}.yml: a service's name is 32 characters at most, lowercase letters, digits and hyphens" if !can(regex("^[a-z][a-z0-9-]{0,31}$", name))],
    flatten([for name, f in local.files : [
      for block, allowed in local.block_keys : "${name}.yml: ${block} takes ${join(", ", allowed)}"
      if can(f[block]) && !alltrue([for k in try(keys(f[block]), ["?"]) : contains(allowed, k)])
    ]]),
    [for name, f in local.files : "${name}.yml: needs ${join(", ", [for k in ["cpu", "memory", "desired_count"] : k if !can(f[k])])}" if !alltrue([for k in ["cpu", "memory", "desired_count"] : can(f[k])])],
    [for name, f in local.files : "${name}.yml: cpu is one of Fargate's sizes: ${join(", ", local.fargate_cpu)}" if can(f.cpu) && !contains(local.fargate_cpu, try(tonumber(f.cpu), 0))],
    [for name, cs in local.definitions : "${name}.yml: container_definitions is a list of at least one container" if length(cs) == 0],
    [for name, cs in local.definitions : "${name}.yml: a container in container_definitions takes ${join(", ", local.definition_keys)}, and needs name and image" if !alltrue([for c in cs : can(c.name) && can(c.image) && alltrue([for k in try(keys(c), ["?"]) : contains(local.definition_keys, k)])])],
    [for name, cs in local.containers : "${name}.yml: container names ${join(", ", distinct([for c in cs : c.name if length([for d in cs : d if d.name == c.name]) > 1]))} are used more than once; each container's name is its own" if length(distinct([for c in cs : c.name])) != length(cs)],
    [for name, cs in local.definitions : "${name}.yml: portMappings is a list of containerPort; environment of name and value; secrets of name and valueFrom" if !alltrue([for c in cs : alltrue(concat(
      [for p in try(tolist(c.portMappings), can(c.portMappings) ? [{ "?" = 1 }] : []) : can(tonumber(p.containerPort)) && length(keys(p)) == 1],
      [for e in try(tolist(c.environment), can(c.environment) ? [{ "?" = 1 }] : []) : can(e.name) && can(e.value) && length(keys(e)) == 2],
      [for s in try(tolist(c.secrets), can(c.secrets) ? [{ "?" = 1 }] : []) : can(s.name) && can(s.valueFrom) && length(keys(s)) == 2],
    ))])],
    [for name, cs in local.definitions : "${name}.yml: a container's healthCheck takes ${join(", ", local.container_hc_keys)}, and needs command" if !alltrue([for c in cs : !can(c.healthCheck) || try(can(c.healthCheck.command) && alltrue([for k in keys(c.healthCheck) : contains(local.container_hc_keys, k)]), false)])],
    [for name, cs in local.containers : "${name}.yml: ${join(", ", flatten([for c in cs : [for e in c.environment : e.name if can(regex(local.secret_name, e.name))]]))} looks like a secret: environment never holds one; list it under secrets with valueFrom: <ARN of a Secrets Manager secret or Parameter Store parameter>" if anytrue(flatten([for c in cs : [for e in c.environment : can(regex(local.secret_name, e.name))]]))],
    [for name, cs in local.containers : "${name}.yml: a secret's valueFrom is the full ARN of a Secrets Manager secret or Parameter Store parameter, never the value itself" if !alltrue(flatten([for c in cs : [for s in c.secrets : can(regex(local.secret_arn, s.valueFrom))]]))],
    [for name, f in local.files : "${name}.yml: deployment_controller.type is ${join(" or ", local.controllers)}" if !contains(local.controllers, local.controller[name])],
    [for name, f in local.files : "${name}.yml: deployment_group is CodeDeploy's (all at once, canary, linear), so it needs deployment_controller.type CODE_DEPLOY; an ECS deployment is ECS's own" if local.controller[name] != "CODE_DEPLOY" && can(f.deployment_group)],
    [for name in local.blue_green : "${name}.yml: deployment_controller.type CODE_DEPLOY needs deployment_group.deployment_config_name, such as CodeDeployDefault.ECSAllAtOnce" if !can(tostring(local.files[name].deployment_group.deployment_config_name))],
    [for name in local.blue_green : "${name}.yml: deployment_group.blue_green_deployment_config takes terminate_blue_instances_on_deployment_success.termination_wait_time_in_minutes" if can(local.files[name].deployment_group.blue_green_deployment_config) && !try(keys(local.files[name].deployment_group.blue_green_deployment_config) == ["terminate_blue_instances_on_deployment_success"] && keys(local.files[name].deployment_group.blue_green_deployment_config.terminate_blue_instances_on_deployment_success) == ["termination_wait_time_in_minutes"], false)],
    [for name, f in local.files : "${name}.yml: ${try(f.deployment_group.deployment_config_name, "")} is for servers; a service uses an ECS one, such as CodeDeployDefault.ECSAllAtOnce, CodeDeployDefault.ECSCanary10Percent5Minutes or CodeDeployDefault.ECSLinear10PercentEvery1Minutes" if local.controller[name] == "CODE_DEPLOY" && startswith(try(tostring(f.deployment_group.deployment_config_name), ""), "CodeDeployDefault.") && !can(regex(local.ecs_config_pattern, try(tostring(f.deployment_group.deployment_config_name), "")))],
    [for name in local.blue_green : "${name}.yml: CODE_DEPLOY moves traffic between two target groups, so it needs a listener_rule" if !can(local.files[name].listener_rule)],
    [for name, f in local.files : "${name}.yml: listener_rule needs a container with portMappings to forward to" if can(f.listener_rule) && length(local.ported[name]) == 0],
    [for name, f in local.files : "${name}.yml: target_group is the load balancer's, so it needs a listener_rule" if can(f.target_group) && !can(f.listener_rule)],
    [for name, f in local.files : "${name}.yml: target_group.health_check takes ${join(", ", local.health_keys)}" if can(f.target_group.health_check) && !alltrue([for k in try(keys(f.target_group.health_check), ["?"]) : contains(local.health_keys, k)])],
    [for r in local.routes : "${r.service}.yml: listener_rule takes ${join(", ", local.rule_keys)}" if !alltrue([for k in r.keys : contains(local.rule_keys, k)])],
    [for r in local.routes : "${r.service}.yml: listener_arn is <load balancer>/<port>, such as services/443" if !can(regex("^[a-z][a-z0-9-]*/[0-9]+$", r.listener_arn))],
    [for r in local.routes : "${r.service}.yml: listener_rule's condition is host_header.values and/or path_pattern.values, at least one, at most 5 together" if length(r.hosts) + length(r.paths) == 0 || length(r.hosts) + length(r.paths) > 5 || !alltrue([for k in r.conditions : contains(["host_header", "path_pattern"], k)])],
    [for r in local.routes : "${r.service}.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)" if r.priority < 1000],
    [for p in distinct(local.priorities) : "priority ${split(":", p)[2]} on ${split(":", p)[0]}:${split(":", p)[1]} is used by more than one service" if length([for x in local.priorities : x if x == p]) > 1],
    [for name, f in local.files : "${name}.yml: appautoscaling_target needs min_capacity <= desired_count <= max_capacity" if can(f.appautoscaling_target) && !try(f.appautoscaling_target.min_capacity <= f.desired_count && f.desired_count <= f.appautoscaling_target.max_capacity, false)],
    [for name, f in local.files : "${name}.yml: appautoscaling_policy.target_tracking_scaling_policy_configuration is target_value and predefined_metric_specification.predefined_metric_type (${join(", ", local.fargate_metrics)})" if can(f.autoscaling) && !try(contains(local.fargate_metrics, local.scaling_metrics[name]) && can(tonumber(local.scaling[name].target_value)) && length(keys(local.scaling[name])) == 2 && keys(local.scaling[name].predefined_metric_specification) == ["predefined_metric_type"], false)],
    [for name, f in local.files : "${name}.yml: scaling on ALBRequestCountPerTarget needs a listener_rule and an ECS deployment (CODE_DEPLOY swaps the target group it counts)" if local.scaling_metrics[name] == "ALBRequestCountPerTarget" && (!can(f.listener_rule) || local.controller[name] != "ECS")],
    [for name, gs in local.group_names : "${name}.yml: network_configuration.security_groups lists 1 to 5 groups, by name from the security-groups stack" if length(gs) == 0 || length(gs) > 5],
    [for name, ss in local.subnet_names : "${name}.yml: network_configuration.subnets lists the subnets, by name such as private-az1, from ${var.environment}'s VPC in ${var.region}: ${join(", ", local.known_subnets)}" if length(ss) == 0 || !alltrue([for s in ss : startswith(s, "subnet-") || contains(local.known_subnets, s)])],
    [for name, f in local.files : "${name}.yml: statement is a list of actions and resources, with effect and condition (test, variable, values) if wanted" if can(f.statement) && !alltrue([for s in try([for x in f.statement : x], [{ "?" = 1 }]) : can(s.actions) && can(s.resources) && alltrue([for k in keys(s) : contains(local.statement_keys, k)]) && alltrue([for c in try([for x in s.condition : x], can(s.condition) ? [{ "?" = 1 }] : []) : can(c.test) && can(c.variable) && can(tolist(c.values))])])],
  )
  usable = length(local.problems) == 0
}
