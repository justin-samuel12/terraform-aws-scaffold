resource "aws_lb" "load_balancer" {
  name                       = var.name
  load_balancer_type         = var.load_balancer_type
  internal                   = var.internal
  subnets                    = var.subnets
  security_groups            = var.security_groups
  enable_deletion_protection = true
  drop_invalid_header_fields = var.load_balancer_type == "application" ? true : null

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.name
    enabled = true
  }

  tags = { Name = "${local.name_prefix}${local.short_name}" }
}

resource "aws_lb_target_group" "targets" {
  for_each = var.target_groups

  name                 = local.target_group_names[each.key]
  vpc_id               = var.vpc_id
  port                 = each.value.port
  protocol             = each.value.protocol
  target_type          = each.value.target_type
  deregistration_delay = each.value.deregistration_delay

  dynamic "health_check" {
    for_each = each.value.health_check == null ? [] : [each.value.health_check]
    content {
      enabled             = health_check.value.enabled
      path                = health_check.value.path
      port                = health_check.value.port
      protocol            = health_check.value.protocol
      matcher             = health_check.value.matcher
      interval            = health_check.value.interval
      timeout             = health_check.value.timeout
      healthy_threshold   = health_check.value.healthy_threshold
      unhealthy_threshold = health_check.value.unhealthy_threshold
    }
  }

  tags = { Name = "${local.name_prefix}${local.short_name}-${each.key}", Key = "${var.name}-${each.key}" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "listeners" {
  for_each = local.listeners

  load_balancer_arn = aws_lb.load_balancer.arn
  port              = each.value.port
  protocol          = each.value.protocol
  ssl_policy        = contains(["HTTPS", "TLS"], each.value.protocol) ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = each.value.certificate_arn

  default_action {
    type             = each.value.default_action.type
    target_group_arn = each.value.default_action.target_group_arn == null ? null : try(aws_lb_target_group.targets[each.value.default_action.target_group_arn].arn, each.value.default_action.target_group_arn)

    dynamic "redirect" {
      for_each = each.value.default_action.redirect == null ? [] : [each.value.default_action.redirect]
      content {
        host        = redirect.value.host
        path        = redirect.value.path
        port        = redirect.value.port
        protocol    = redirect.value.protocol
        query       = redirect.value.query
        status_code = redirect.value.status_code
      }
    }

    dynamic "fixed_response" {
      for_each = each.value.default_action.fixed_response == null ? [] : [each.value.default_action.fixed_response]
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }
  }

  tags = { Name = "${local.name_prefix}${local.short_name}-${each.key}" }
}

resource "aws_lb_listener_rule" "rules" {
  for_each = var.listener_rules

  listener_arn = try(aws_lb_listener.listeners[each.value.listener_arn].arn, each.value.listener_arn)
  priority     = each.value.priority

  action {
    type             = each.value.action.type
    target_group_arn = each.value.action.target_group_arn == null ? null : try(aws_lb_target_group.targets[each.value.action.target_group_arn].arn, each.value.action.target_group_arn)

    dynamic "redirect" {
      for_each = each.value.action.redirect == null ? [] : [each.value.action.redirect]
      content {
        host        = redirect.value.host
        path        = redirect.value.path
        port        = redirect.value.port
        protocol    = redirect.value.protocol
        query       = redirect.value.query
        status_code = redirect.value.status_code
      }
    }

    dynamic "fixed_response" {
      for_each = each.value.action.fixed_response == null ? [] : [each.value.action.fixed_response]
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.condition.host_header == null ? [] : [each.value.condition.host_header]
    content {
      host_header {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.condition.path_pattern == null ? [] : [each.value.condition.path_pattern]
    content {
      path_pattern {
        values = condition.value.values
      }
    }
  }

  tags = { Name = "${local.name_prefix}${local.short_name}-${each.key}" }
}

resource "aws_lb_listener_certificate" "additional" {
  for_each = var.listener_certificates

  listener_arn    = aws_lb_listener.listeners[each.value.listener_arn].arn
  certificate_arn = each.value.certificate_arn
}
