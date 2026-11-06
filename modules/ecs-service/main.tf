resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })
}

resource "aws_iam_role" "execution" {
  name                 = local.execution_role_name
  description          = "ECS starting ${var.name}'s tasks in ${var.environment}, ${var.region}"
  max_session_duration = 3600
  assume_role_policy   = local.assume_role_policy

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}-${var.region}-execution", Service = var.name })

  lifecycle {
    precondition {
      condition     = length(local.execution_role_name) <= 64
      error_message = "${local.execution_role_name} is longer than the 64 characters IAM allows; shorten the service's name."
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = local.execution_role_name
  role   = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.execution_statements })
}

resource "aws_iam_role" "task" {
  name                 = local.task_role_name
  description          = "${var.name}'s containers in ${var.environment}, ${var.region}"
  max_session_duration = 3600
  assume_role_policy   = local.assume_role_policy

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}-${var.region}", Service = var.name })
}

resource "aws_iam_role_policy" "task" {
  count = length(local.task_statements) > 0 ? 1 : 0

  name   = local.task_role_name
  role   = aws_iam_role.task.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.task_statements })
}

resource "aws_ecs_task_definition" "task" {
  family                   = local.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode(local.container_definitions)
  skip_destroy             = true

  dynamic "runtime_platform" {
    for_each = var.runtime_platform == null ? [] : [var.runtime_platform]
    content {
      cpu_architecture        = runtime_platform.value.cpu_architecture
      operating_system_family = runtime_platform.value.operating_system_family
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })

  depends_on = [aws_iam_role_policy.execution]
}

resource "aws_lb_target_group" "targets" {
  for_each = local.target_group_names

  name                 = each.value
  vpc_id               = var.vpc_id
  port                 = local.front.port
  protocol             = "HTTP"
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = var.health_check.path
    protocol            = "HTTP"
    matcher             = var.health_check.matcher
    interval            = var.health_check.interval
    timeout             = var.health_check.timeout
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}-${each.key}", Service = var.name })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.vpc_id != null
      error_message = "A service with routes needs the VPC for its target groups."
    }
  }
}

resource "aws_ecs_service" "service" {
  count = !local.blue_green ? 1 : 0

  name                               = local.service_name
  cluster                            = var.cluster.arn
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  platform_version                   = "LATEST"
  enable_execute_command             = var.execute_command != null
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  health_check_grace_period_seconds  = local.routed ? 60 : null
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.network_configuration.subnets
    security_groups  = var.network_configuration.security_groups
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = local.routed ? [local.live_target] : []
    content {
      target_group_arn = aws_lb_target_group.targets[load_balancer.value].arn
      container_name   = local.front.name
      container_port   = local.front.port
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.routes, aws_iam_role_policy.task]
}

moved {
  from = aws_ecs_service.scaled
  to   = aws_ecs_service.service
}

resource "aws_ecs_service" "blue_green" {
  count = local.blue_green ? 1 : 0

  name                               = local.service_name
  cluster                            = var.cluster.arn
  task_definition                    = aws_ecs_task_definition.task.arn
  desired_count                      = var.desired_count
  platform_version                   = "LATEST"
  enable_execute_command             = var.execute_command != null
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.network_configuration.subnets
    security_groups  = var.network_configuration.security_groups
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.targets["blue"].arn
    container_name   = local.front.name
    container_port   = local.front.port
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })

  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count, network_configuration, capacity_provider_strategy, platform_version]
  }

  depends_on = [aws_lb_listener_rule.routes_blue_green, aws_iam_role_policy.task]
}

resource "aws_lb_listener_rule" "routes" {
  for_each = local.blue_green ? {} : { for i, r in var.routes : tostring(i) => r }

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  dynamic "condition" {
    for_each = length(each.value.hosts) > 0 ? [each.value.hosts] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.paths) > 0 ? [each.value.paths] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.targets[local.live_target].arn
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}-${each.key}", Service = var.name })
}

resource "aws_lb_listener_rule" "routes_blue_green" {
  for_each = local.blue_green ? { for i, r in var.routes : tostring(i) => r } : {}

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  dynamic "condition" {
    for_each = length(each.value.hosts) > 0 ? [each.value.hosts] : []
    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.paths) > 0 ? [each.value.paths] : []
    content {
      path_pattern {
        values = condition.value
      }
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.targets["blue"].arn
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}-${each.key}", Service = var.name })

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_appautoscaling_target" "service" {
  service_namespace  = "ecs"
  resource_id        = "service/${var.cluster.name}/${local.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = local.scaled ? var.autoscaling.min_capacity : var.desired_count
  max_capacity       = local.scaled ? var.autoscaling.max_capacity : var.desired_count

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })

  depends_on = [aws_ecs_service.service, aws_ecs_service.blue_green]
}

resource "aws_appautoscaling_policy" "service" {
  count = local.scaled ? 1 : 0

  name               = "${local.service_name}-${lower(replace(var.autoscaling.target_tracking_scaling_policy_configuration.predefined_metric_specification.predefined_metric_type, "ECSService", ""))}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service.service_namespace
  resource_id        = aws_appautoscaling_target.service.resource_id
  scalable_dimension = aws_appautoscaling_target.service.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.target_tracking_scaling_policy_configuration.target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = var.autoscaling.target_tracking_scaling_policy_configuration.predefined_metric_specification.predefined_metric_type
      resource_label         = var.autoscaling.target_tracking_scaling_policy_configuration.predefined_metric_specification.predefined_metric_type == "ALBRequestCountPerTarget" ? "${var.load_balancer_arn_suffix}/${aws_lb_target_group.targets[local.live_target].arn_suffix}" : null
    }
  }
}

resource "aws_codedeploy_app" "application" {
  count = local.blue_green ? 1 : 0

  name             = local.service_name
  compute_platform = "ECS"

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })
}

resource "aws_codedeploy_deployment_group" "group" {
  count = local.blue_green ? 1 : 0

  app_name               = aws_codedeploy_app.application[0].name
  deployment_group_name  = local.service_name
  service_role_arn       = var.codedeploy_role_arn
  deployment_config_name = var.deployment_group.deployment_config_name

  auto_rollback_configuration {
    enabled = length(var.deployment_group.rollback_events) > 0
    events  = var.deployment_group.rollback_events
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.deployment_group.termination_wait_time_in_minutes
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = var.cluster.name
    service_name = aws_ecs_service.blue_green[0].name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = distinct([for r in var.routes : r.listener_arn])
      }

      target_group {
        name = aws_lb_target_group.targets["blue"].name
      }

      target_group {
        name = aws_lb_target_group.targets["green"].name
      }
    }
  }

  tags = merge(var.tags, { Name = "${local.name_prefix}${var.name}", Service = var.name })
}
