module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "blueprint" {
  source = "../../modules/blueprint"

  files       = local.raw_files
  dir         = local.blueprints_dir
  label       = "blueprints/containers"
  body        = "service"
  example     = "ecs-service/v1"
  environment = var.environment
  region      = var.region
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"
  count  = local.usable && length(local.files) > 0 ? 1 : 0

  environment = var.environment
  kms_key_arn = data.aws_kms_key.data[0].arn
}

module "codedeploy_role" {
  source = "../../modules/iam-role"
  count  = local.usable && length(local.blue_green) > 0 ? 1 : 0

  roles = {
    "codedeploy-ecs-${var.environment}-${var.region}" = {
      description      = "CodeDeploy deploying ${var.environment}'s containers in ${var.region}"
      services         = ["codedeploy"]
      managed_policies = ["AWSCodeDeployRoleForECS"]
    }
  }
}

module "ecs_service" {
  source   = "../../modules/ecs-service"
  for_each = { for name, f in local.files : name => f if local.usable }

  tags = { for k, v in try(each.value.tags, {}) : k => tostring(v) }

  name        = each.key
  environment = var.environment
  region      = var.region
  cluster     = { arn = module.ecs_cluster[0].arn, name = module.ecs_cluster[0].name }
  execute_command = try(tobool(each.value.enable_execute_command), false) ? {
    log_group_arn = module.ecs_cluster[0].exec.log_group_arn
    kms_key_arn   = module.ecs_cluster[0].exec.kms_key_arn
  } : null

  cpu                   = tonumber(each.value.cpu)
  memory                = tonumber(each.value.memory)
  runtime_platform      = can(each.value.runtime_platform) ? { cpu_architecture = try(tostring(each.value.runtime_platform.cpu_architecture), null), operating_system_family = try(tostring(each.value.runtime_platform.operating_system_family), null) } : null
  container_definitions = local.containers[each.key]
  desired_count         = tonumber(each.value.desired_count)
  statements = [for s in try(each.value.statement, []) : {
    effect    = try(s.effect, "Allow")
    actions   = [for a in s.actions : tostring(a)]
    resources = [for r in s.resources : replace(replace(replace(tostring(r), "{app}", each.key), "{environment}", var.environment), "{region}", var.region)]
    condition = [for c in try(s.condition, []) : { test = tostring(c.test), variable = tostring(c.variable), values = [for v in c.values : replace(replace(replace(tostring(v), "{app}", each.key), "{environment}", var.environment), "{region}", var.region)] }]
  }]
  capacity_provider_strategy = [for s in try(each.value.capacity_provider_strategy, [{ capacity_provider = "FARGATE" }]) : {
    capacity_provider = tostring(s.capacity_provider)
    weight            = try(tonumber(s.weight), 1)
    base              = try(tonumber(s.base), 0)
  }]

  network_configuration = {
    subnets         = [for s in local.subnet_names[each.key] : startswith(s, "subnet-") ? s : data.aws_subnet.subnets[s].id]
    security_groups = [for g in local.group_names[each.key] : startswith(g, "sg-") ? g : data.aws_security_group.groups[g].id]
  }
  vpc_id = data.aws_vpc.vpc[0].id
  health_check = {
    path                = try(tostring(each.value.target_group.health_check.path), null)
    matcher             = try(tostring(each.value.target_group.health_check.matcher), null)
    interval            = try(tonumber(each.value.target_group.health_check.interval), null)
    timeout             = try(tonumber(each.value.target_group.health_check.timeout), null)
    healthy_threshold   = try(tonumber(each.value.target_group.health_check.healthy_threshold), null)
    unhealthy_threshold = try(tonumber(each.value.target_group.health_check.unhealthy_threshold), null)
  }
  routes = [
    for r in local.routes : {
      listener_arn = data.aws_lb_listener.listeners["${r.load_balancer}:${r.listener}"].arn
      hosts        = r.hosts
      paths        = r.paths
      priority     = r.priority
    }
    if r.service == each.key
  ]
  load_balancer_arn_suffix = try(data.aws_lb.load_balancers[[for r in local.routes : r.load_balancer if r.service == each.key][0]].arn_suffix, null)

  autoscaling = can(each.value.appautoscaling_target) ? {
    min_capacity = tonumber(each.value.appautoscaling_target.min_capacity)
    max_capacity = tonumber(each.value.appautoscaling_target.max_capacity)
    target_tracking_scaling_policy_configuration = {
      target_value                    = tonumber(local.scaling[each.key].target_value)
      predefined_metric_specification = { predefined_metric_type = local.scaling_metrics[each.key] }
    }
  } : null

  deployment_controller              = local.controller[each.key]
  deployment_minimum_healthy_percent = try(tonumber(each.value.deployment_minimum_healthy_percent), null)
  deployment_maximum_percent         = try(tonumber(each.value.deployment_maximum_percent), null)
  deployment_group = {
    deployment_config_name           = try(tostring(each.value.deployment_group.deployment_config_name), null)
    termination_wait_time_in_minutes = try(tonumber(each.value.deployment_group.blue_green_deployment_config.terminate_blue_instances_on_deployment_success.termination_wait_time_in_minutes), null)
  }
  codedeploy_role_arn = local.controller[each.key] == "CODE_DEPLOY" ? module.codedeploy_role[0].arns["codedeploy-ecs-${var.environment}-${var.region}"] : null
}
