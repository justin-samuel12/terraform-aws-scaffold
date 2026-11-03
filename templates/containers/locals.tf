locals {
  config_dir = coalesce(var.config_dir, path.root)
  files      = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => merge({}, try(yamldecode(file("${local.config_dir}/${name}")), {})) }
  network    = module.ip_plan.networks["${var.environment}/${var.region}"]

  # A service: its size and network, one container (image, port) or several (container_definitions), then optional features.
  container_keys = ["image", "port", "command", "environment", "secrets"]
  service_keys   = ["cpu", "memory", "desired_count", "tier", "security_groups", "runtime_platform", "capacity_provider_strategy", "enable_execute_command", "statement", "container_definitions"]
  feature_keys   = ["health_check", "listener_rules", "autoscaling", "deployment"]
  file_keys      = concat(local.service_keys, local.container_keys, local.feature_keys)
  block_keys = {
    health_check     = ["path", "matcher", "interval", "timeout", "healthy_threshold", "unhealthy_threshold"]
    autoscaling      = ["min_capacity", "max_capacity", "target_tracking_configuration"]
    deployment       = ["strategy", "deployment_config_name", "minimum_healthy_percent", "maximum_percent", "termination_wait_time_in_minutes"]
    runtime_platform = ["cpu_architecture"]
  }
  definition_keys    = ["name", "image", "port", "essential", "command", "environment", "secrets", "health_check"]
  container_hc_keys  = ["command", "interval", "timeout", "retries", "start_period"]
  rule_keys          = ["load_balancer", "listener", "host_header", "path_pattern", "priority"]
  strategies         = ["rolling", "blue_green"]
  secret_name        = "(?i)(password|secret|token|private_key|api_key|credential)"
  secret_arn         = "^arn:aws[a-z-]*:(secretsmanager|ssm):[a-z0-9-]+:[0-9]{12}:(secret:|parameter/)"
  fargate_cpu        = [256, 512, 1024, 2048, 4096, 8192, 16384]
  fargate_metrics    = ["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization", "ALBRequestCountPerTarget"]
  ecs_config_pattern = "^CodeDeployDefault\\.ECS"

  # Every service's containers, in the module's shape: a single image and port becomes one container named after the service.
  containers = {
    for name, f in local.files : name => [
      for c in concat(try([for x in f.container_definitions : x], []), [for x in [merge(f, { name = name })] : x if !can(f.container_definitions)]) : {
        name        = try(tostring(c.name), "?")
        image       = try(tostring(c.image), "")
        port        = try(tonumber(c.port), null)
        essential   = try(tobool(c.essential), true)
        command     = try([for x in c.command : tostring(x)], null)
        environment = { for k, v in try(c.environment, {}) : k => tostring(v) }
        secrets     = { for k, v in try(c.secrets, {}) : k => tostring(v) }
        health_check = can(c.health_check.command) ? {
          command      = [for x in c.health_check.command : tostring(x)]
          interval     = try(tonumber(c.health_check.interval), 30)
          timeout      = try(tonumber(c.health_check.timeout), 5)
          retries      = try(tonumber(c.health_check.retries), 3)
          start_period = try(tonumber(c.health_check.start_period), 0)
        } : null
      }
    ]
  }
  strategy   = { for name, f in local.files : name => try(tostring(f.deployment.strategy), "rolling") }
  blue_green = toset([for name, s in local.strategy : name if s == "blue_green"])

  # Every route, flattened, so they can be checked across services and looked up once.
  routes = flatten([for name, f in local.files : [for r in try([for x in f.listener_rules : x], []) : {
    service       = name
    load_balancer = try(tostring(r.load_balancer), "?")
    listener      = tostring(try(r.listener, 443))
    hosts         = try([for h in r.host_header : tostring(h)], [])
    paths         = try([for p in r.path_pattern : tostring(p)], [])
    priority      = try(tonumber(r.priority), 0)
    keys          = try(keys(r), ["?"])
  }]])
  listener_keys = distinct([for r in local.routes : "${r.load_balancer}:${r.listener}"])
  priorities    = [for r in local.routes : "${r.load_balancer}:${r.listener}:${r.priority}"]

  problems = concat(
    [for name, f in local.files : "${name}.yml: keys are ${join(", ", local.file_keys)}" if length(f) == 0 || !alltrue([for k in keys(f) : contains(local.file_keys, k)])],
    [for name in keys(local.files) : "${name}.yml: a service's name is 32 characters at most, lowercase letters, digits and hyphens" if !can(regex("^[a-z][a-z0-9-]{0,31}$", name))],
    flatten([for name, f in local.files : [
      for block, allowed in local.block_keys : "${name}.yml: ${block} takes ${join(", ", allowed)}"
      if can(f[block]) && !alltrue([for k in try(keys(f[block]), ["?"]) : contains(allowed, k)])
    ]]),
    [for name, f in local.files : "${name}.yml: give image (and port) for one container, or container_definitions for several, not both" if can(f.container_definitions) == anytrue([for k in local.container_keys : can(f[k])])],
    [for name, f in local.files : "${name}.yml: container_definitions take ${join(", ", local.definition_keys)}; each needs a name and an image" if can(f.container_definitions) && !alltrue([for c in try([for x in f.container_definitions : x], [{ "?" = 1 }]) : can(c.name) && can(c.image) && alltrue([for k in keys(c) : contains(local.definition_keys, k)])])],
    [for name, f in local.files : "${name}.yml: a container's health_check takes ${join(", ", local.container_hc_keys)}, and needs command" if !alltrue([for c in try([for x in f.container_definitions : x], []) : !can(c.health_check) || try(can(c.health_check.command) && alltrue([for k in keys(c.health_check) : contains(local.container_hc_keys, k)]), false)])],
    [for name, cs in local.containers : "${name}.yml: needs an image" if anytrue([for c in cs : trimspace(c.image) == ""]) && !can(local.files[name].container_definitions)],
    [for name, cs in local.containers : "${name}.yml: ${join(", ", flatten([for c in cs : [for k in keys(c.environment) : k if can(regex(local.secret_name, k))]]))} looks like a secret: environment variables never hold one; list it under secrets as NAME: <ARN of a Secrets Manager secret or Parameter Store parameter>" if anytrue(flatten([for c in cs : [for k in keys(c.environment) : can(regex(local.secret_name, k))]]))],
    [for name, cs in local.containers : "${name}.yml: secrets are NAME: <the full ARN of a Secrets Manager secret or Parameter Store parameter>, never the value itself" if !alltrue(flatten([for c in cs : [for v in values(c.secrets) : can(regex(local.secret_arn, v))]]))],
    [for name, f in local.files : "${name}.yml: cpu is one of Fargate's sizes: ${join(", ", local.fargate_cpu)}" if can(f.cpu) && !contains(local.fargate_cpu, try(tonumber(f.cpu), 0))],
    [for name, f in local.files : "${name}.yml: deployment.strategy is ${join(" or ", local.strategies)}" if !contains(local.strategies, local.strategy[name])],
    [for name, f in local.files : "${name}.yml: deployment_config_name is CodeDeploy's (all at once, canary, linear), so it needs strategy: blue_green; a rolling deployment is ECS's own" if local.strategy[name] == "rolling" && can(f.deployment.deployment_config_name)],
    [for name, f in local.files : "${name}.yml: ${try(f.deployment.deployment_config_name, "")} is for servers; a service uses an ECS one, such as CodeDeployDefault.ECSAllAtOnce, CodeDeployDefault.ECSCanary10Percent5Minutes or CodeDeployDefault.ECSLinear10PercentEvery1Minutes" if local.strategy[name] == "blue_green" && startswith(try(tostring(f.deployment.deployment_config_name), ""), "CodeDeployDefault.") && !can(regex(local.ecs_config_pattern, try(tostring(f.deployment.deployment_config_name), "")))],
    [for name in local.blue_green : "${name}.yml: blue_green moves traffic between two target groups, so it needs listener_rules" if length(try(local.files[name].listener_rules, [])) == 0],
    [for name, f in local.files : "${name}.yml: listener_rules need a container with a port to forward to" if length(try(f.listener_rules, [])) > 0 && !anytrue([for c in local.containers[name] : c.port != null])],
    [for name, f in local.files : "${name}.yml: health_check is the load balancer's, so it needs listener_rules" if can(f.health_check) && length(try(f.listener_rules, [])) == 0],
    [for r in local.routes : "${r.service}.yml: listener_rules take ${join(", ", local.rule_keys)}" if !alltrue([for k in r.keys : contains(local.rule_keys, k)])],
    [for r in local.routes : "${r.service}.yml: a listener rule matches at least one host_header or path_pattern" if length(r.hosts) + length(r.paths) == 0],
    [for r in local.routes : "${r.service}.yml: listener rule priorities are 1000 and up (1 to 999 are the load balancer's own rules)" if r.priority < 1000],
    [for p in distinct(local.priorities) : "priority ${split(":", p)[2]} on ${split(":", p)[0]}:${split(":", p)[1]} is used by more than one service" if length([for x in local.priorities : x if x == p]) > 1],
    [for name, f in local.files : "${name}.yml: autoscaling needs min_capacity <= desired_count <= max_capacity" if can(f.autoscaling) && !try(f.autoscaling.min_capacity <= try(f.desired_count, f.autoscaling.min_capacity) && try(f.desired_count, f.autoscaling.min_capacity) <= f.autoscaling.max_capacity, false)],
    [for name, f in local.files : "${name}.yml: autoscaling's target_tracking_configuration is predefined_metric_type (${join(", ", local.fargate_metrics)}) and target_value" if can(f.autoscaling) && !try(contains(local.fargate_metrics, try(f.autoscaling.target_tracking_configuration.predefined_metric_type, "ECSServiceAverageCPUUtilization")) && can(tonumber(f.autoscaling.target_tracking_configuration.target_value)) && alltrue([for k in keys(f.autoscaling.target_tracking_configuration) : contains(["predefined_metric_type", "target_value"], k)]), false)],
    [for name, f in local.files : "${name}.yml: scaling on ALBRequestCountPerTarget needs listener_rules and a rolling deployment (blue/green swaps the target group it counts)" if try(f.autoscaling.target_tracking_configuration.predefined_metric_type, "") == "ALBRequestCountPerTarget" && (length(try(f.listener_rules, [])) == 0 || local.strategy[name] != "rolling")],
    [for name, f in local.files : "${name}.yml: security_groups lists at least one, by name, from the security-groups stack" if length(try([for x in f.security_groups : x], [])) == 0],
    [for name, f in local.files : "${name}.yml: ${var.environment}'s VPC in ${var.region} has no ${try(f.tier, "private")} tier" if !contains(keys(local.network.subnets), try(tostring(f.tier), "private"))],
    [for name, f in local.files : "${name}.yml: statement is a list of actions and resources, with effect if wanted" if can(f.statement) && !alltrue([for s in try([for x in f.statement : x], [{ "?" = 1 }]) : can(s.actions) && can(s.resources) && alltrue([for k in keys(s) : contains(["effect", "actions", "resources"], k)])])],
  )
  usable = length(local.problems) == 0
}
