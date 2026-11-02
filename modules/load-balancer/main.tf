resource "aws_lb" "load_balancer" {
  name                       = var.name
  load_balancer_type         = var.type
  internal                   = var.internal
  subnets                    = var.subnet_ids
  security_groups            = var.security_group_ids
  enable_deletion_protection = true
  drop_invalid_header_fields = var.type == "application" ? true : null

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.name
    enabled = true
  }

  tags = { Name = var.name }
}

resource "aws_lb_target_group" "targets" {
  for_each = var.targets

  name                 = local.target_group_names[each.key]
  vpc_id               = var.vpc_id
  port                 = each.value.port
  protocol             = each.value.protocol
  target_type          = "instance"
  deregistration_delay = 60

  dynamic "health_check" {
    for_each = each.value.health_check_path == null ? [] : [each.value.health_check_path]
    content {
      path    = health_check.value
      matcher = "200-399"
    }
  }

  tags = { Name = "${var.name}-${each.key}" }

  # A new group is built first and every listener and rule moves to it in place; the old one goes last.
  lifecycle {
    create_before_destroy = true
  }
}

# TLS 1.2 and 1.3 only; plain HTTP exists only to redirect to HTTPS.
resource "aws_lb_listener" "listeners" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.load_balancer.arn
  port              = tonumber(each.key)
  protocol          = each.value.protocol
  ssl_policy        = contains(["HTTPS", "TLS"], each.value.protocol) ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = contains(["HTTPS", "TLS"], each.value.protocol) ? var.certificate_arn : null

  dynamic "default_action" {
    for_each = each.value.redirect || each.value.target == null ? [] : [each.value.target]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.targets[default_action.value].arn
    }
  }

  dynamic "default_action" {
    for_each = each.value.redirect ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = !each.value.redirect && each.value.target == null ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not found"
        status_code  = "404"
      }
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}

resource "aws_lb_listener_rule" "rules" {
  for_each = var.rules

  listener_arn = aws_lb_listener.listeners[each.value.listener].arn
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

  dynamic "action" {
    for_each = each.value.target == null ? [] : [each.value.target]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.targets[action.value].arn
    }
  }

  dynamic "action" {
    for_each = each.value.redirect == null ? [] : [each.value.redirect]
    content {
      type = "redirect"
      redirect {
        host        = action.value.host
        path        = action.value.path
        query       = action.value.query
        port        = "443"
        protocol    = "HTTPS"
        status_code = action.value.status_code
      }
    }
  }

  dynamic "action" {
    for_each = each.value.fixed_response == null ? [] : [each.value.fixed_response]
    content {
      type = "fixed-response"
      fixed_response {
        status_code  = action.value.status_code
        content_type = action.value.content_type
        message_body = action.value.body
      }
    }
  }

  tags = { Name = "${var.name}-${each.key}" }
}
