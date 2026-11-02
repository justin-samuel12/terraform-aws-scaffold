data "aws_default_tags" "current" {}

# The image's root device, so the root disk is sized and encrypted whatever the image calls it.
data "aws_ami" "image" {
  filter {
    name   = "image-id"
    values = [var.image_id]
  }
}

resource "aws_launch_template" "group" {
  name                   = local.name
  image_id               = var.image_id
  instance_type          = var.instance_type
  vpc_security_group_ids = var.security_group_ids
  user_data              = var.user_data == null ? null : base64encode(var.user_data)
  ebs_optimized          = true
  update_default_version = true

  iam_instance_profile {
    name = var.instance_profile
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  block_device_mappings {
    device_name = data.aws_ami.image.root_device_name

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_size
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.volumes
    content {
      device_name = block_device_mappings.value.device

      ebs {
        volume_type           = "gp3"
        volume_size           = block_device_mappings.value.size
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        encrypted             = true
        kms_key_id            = var.kms_key_arn
        delete_on_termination = true
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags
  }

  tags = { Name = local.name, Group = var.name }
}

resource "aws_autoscaling_group" "group" {
  name                      = local.name
  vpc_zone_identifier       = var.subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  target_group_arns         = var.target_group_arns
  health_check_type         = length(var.target_group_arns) > 0 ? "ELB" : "EC2"
  health_check_grace_period = 300
  default_instance_warmup   = 300
  enabled_metrics           = ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupMinSize", "GroupMaxSize", "GroupTotalInstances"]

  launch_template {
    id      = aws_launch_template.group.id
    version = aws_launch_template.group.latest_version
  }

  # A new image or settings roll out a few instances at a time, keeping 90% in service.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
  }

  tag {
    key                 = "Name"
    value               = local.name
    propagate_at_launch = false
  }

  tag {
    key                 = "Group"
    value               = var.name
    propagate_at_launch = false
  }

  # Scaling moves desired_capacity; a plan never moves it back.
  lifecycle {
    ignore_changes = [desired_capacity]

    precondition {
      condition     = var.min_size <= var.desired_capacity && var.desired_capacity <= var.max_size && var.min_size >= 0
      error_message = "min_size <= desired_capacity <= max_size."
    }
  }
}

resource "aws_autoscaling_policy" "target_tracking" {
  count = var.target_tracking_configuration == null ? 0 : 1

  name                   = "${local.name}-${lower(var.target_tracking_configuration.predefined_metric_type)}"
  autoscaling_group_name = aws_autoscaling_group.group.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    target_value = var.target_tracking_configuration.target_value

    predefined_metric_specification {
      predefined_metric_type = var.target_tracking_configuration.predefined_metric_type
      resource_label         = var.target_tracking_configuration.resource_label
    }
  }
}
