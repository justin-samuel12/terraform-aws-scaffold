resource "aws_lb_target_group" "group" {
  count = local.routed ? 1 : 0

  name                 = length("${var.environment}-${var.name}") <= 23 ? "${var.environment}-${var.name}-${local.target_group_suffix}" : "${substr("${var.environment}-${var.name}", 0, 23)}-${local.target_group_suffix}"
  vpc_id               = var.vpc_id
  port                 = var.port
  protocol             = var.target.protocol
  target_type          = "instance"
  deregistration_delay = 60
  slow_start           = var.target.slow_start

  health_check {
    path     = var.health
    protocol = var.target.protocol
    matcher  = var.target.matcher
  }

  stickiness {
    enabled         = var.target.stickiness != null
    type            = "lb_cookie"
    cookie_duration = coalesce(var.target.stickiness, 86400)
  }

  tags = { Name = var.name, Group = var.name }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.port != null
      error_message = "A group with routes needs a port."
    }
  }
}

module "servers" {
  source = "../ec2-instance"

  environment        = var.environment
  group              = var.name
  members            = var.servers.members
  image_id           = var.servers.image_id
  security_group_ids = var.servers.security_group_ids
  instance_profile   = var.servers.instance_profile
  kms_key_arn        = var.servers.kms_key_arn
  root_size          = var.servers.root_size
  volumes            = var.servers.volumes
  backup             = var.servers.backup
  user_data          = var.servers.user_data
  tags               = var.servers.tags
  target_groups = merge(
    { for name, t in var.targets : name => { arn = t.arn, port = t.port } },
    local.routed ? { (var.name) = { arn = aws_lb_target_group.group[0].arn, port = var.port } } : {},
  )
}

# Instead of fixed servers: a launch template and an Auto Scaling group, behind the same target groups.
module "autoscaling" {
  source = "../autoscaling-group"
  count  = var.autoscaling == null ? 0 : 1

  name                          = var.name
  environment                   = var.environment
  image_id                      = var.servers.image_id
  instance_type                 = var.instance_type
  security_group_ids            = var.servers.security_group_ids
  instance_profile              = var.servers.instance_profile
  kms_key_arn                   = var.servers.kms_key_arn
  root_size                     = var.servers.root_size
  volumes                       = var.servers.volumes
  user_data                     = var.servers.user_data
  tags                          = var.servers.tags
  subnet_ids                    = var.autoscaling.subnet_ids
  min_size                      = var.autoscaling.min_size
  max_size                      = var.autoscaling.max_size
  desired_capacity              = var.autoscaling.desired_capacity
  target_tracking_configuration = var.autoscaling.target_tracking_configuration
  target_group_arns             = concat(aws_lb_target_group.group[*].arn, [for t in values(var.targets) : t.arn])
}

resource "aws_lb_listener_rule" "routes" {
  for_each = { for i, r in var.routes : tostring(i) => r }

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
    target_group_arn = aws_lb_target_group.group[0].arn
  }

  tags = { Name = "${var.name}-${each.key}", Group = var.name }
}

module "names" {
  source = "../route53-record"

  providers = {
    aws = aws.hub
  }

  records = {
    for n in var.names : n.name => {
      zone_id = n.zone_id
      name    = n.name
      alias   = { name = n.lb_dns_name, zone_id = n.lb_zone_id }
    }
  }
}
