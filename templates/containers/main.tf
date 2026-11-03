module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

# Everything shared is found by name and tags: the VPC, subnets, security groups, the data key, load balancers and listeners.
data "aws_vpc" "vpc" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
    Name        = "vpc-01"
  }
}

# A service's subnets: every zone of its tier.
data "aws_subnets" "tiers" {
  for_each = local.usable ? toset([for f in values(local.files) : try(tostring(f.tier), "private")]) : toset([])

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc[0].id]
  }

  tags = { Tier = each.key }
}

data "aws_security_group" "groups" {
  for_each = local.usable ? toset(flatten([for f in values(local.files) : [for g in try(f.security_groups, []) : tostring(g)]])) : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Name = each.key }
}

data "aws_kms_key" "data" {
  count = local.usable && length(local.files) > 0 ? 1 : 0

  key_id = "alias/${var.environment}-data"
}

data "aws_lb" "load_balancers" {
  for_each = local.usable ? toset([for r in local.routes : r.load_balancer]) : toset([])

  name = "${var.environment}-${each.key}"
}

data "aws_lb_listener" "listeners" {
  for_each = local.usable ? toset(local.listener_keys) : toset([])

  load_balancer_arn = data.aws_lb.load_balancers[split(":", each.key)[0]].arn
  port              = tonumber(split(":", each.key)[1])
}

# One cluster per environment and region, made once any service file exists.
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"
  count  = local.usable && length(local.files) > 0 ? 1 : 0

  environment = var.environment
  kms_key_arn = data.aws_kms_key.data[0].arn
}

# One CodeDeploy service role per environment and region, only when some service deploys blue/green.
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

  name        = each.key
  environment = var.environment
  region      = var.region
  cluster     = { arn = module.ecs_cluster[0].arn, name = module.ecs_cluster[0].name }
  execute_command = try(tobool(each.value.enable_execute_command), true) ? {
    log_group_arn = module.ecs_cluster[0].exec.log_group_arn
    kms_key_arn   = module.ecs_cluster[0].exec.kms_key_arn
  } : null

  cpu           = try(tonumber(each.value.cpu), 256)
  memory        = try(tonumber(each.value.memory), 512)
  architecture  = try(tostring(each.value.runtime_platform.cpu_architecture), "X86_64")
  containers    = local.containers[each.key]
  desired_count = try(tonumber(each.value.desired_count), 2)
  statements = [for s in try(each.value.statement, []) : {
    effect    = try(s.effect, "Allow")
    actions   = [for a in s.actions : tostring(a)]
    resources = [for r in s.resources : replace(replace(replace(tostring(r), "{app}", each.key), "{environment}", var.environment), "{region}", var.region)]
  }]
  capacity_provider_strategy = [for s in try(each.value.capacity_provider_strategy, [{ capacity_provider = "FARGATE" }]) : {
    capacity_provider = tostring(s.capacity_provider)
    weight            = try(tonumber(s.weight), 1)
    base              = try(tonumber(s.base), 0)
  }]

  subnet_ids         = data.aws_subnets.tiers[try(tostring(each.value.tier), "private")].ids
  security_group_ids = [for g in each.value.security_groups : data.aws_security_group.groups[tostring(g)].id]
  vpc_id             = data.aws_vpc.vpc[0].id
  health = {
    path                = try(tostring(each.value.health_check.path), "/")
    matcher             = try(tostring(each.value.health_check.matcher), "200-399")
    interval            = try(tonumber(each.value.health_check.interval), 30)
    timeout             = try(tonumber(each.value.health_check.timeout), 5)
    healthy_threshold   = try(tonumber(each.value.health_check.healthy_threshold), 3)
    unhealthy_threshold = try(tonumber(each.value.health_check.unhealthy_threshold), 3)
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

  autoscaling = can(each.value.autoscaling) ? {
    min_capacity           = each.value.autoscaling.min_capacity
    max_capacity           = each.value.autoscaling.max_capacity
    predefined_metric_type = try(each.value.autoscaling.target_tracking_configuration.predefined_metric_type, "ECSServiceAverageCPUUtilization")
    target_value           = each.value.autoscaling.target_tracking_configuration.target_value
  } : null

  deployment = {
    strategy                         = local.strategy[each.key]
    deployment_config_name           = try(tostring(each.value.deployment.deployment_config_name), null)
    minimum_healthy_percent          = try(tonumber(each.value.deployment.minimum_healthy_percent), 100)
    maximum_percent                  = try(tonumber(each.value.deployment.maximum_percent), 200)
    termination_wait_time_in_minutes = try(tonumber(each.value.deployment.termination_wait_time_in_minutes), 5)
  }
  codedeploy_role_arn = local.strategy[each.key] == "blue_green" ? module.codedeploy_role[0].arns["codedeploy-ecs-${var.environment}-${var.region}"] : null
}
