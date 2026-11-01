resource "aws_ssm_patch_baseline" "baselines" {
  for_each = local.baselines

  name             = "${var.environment}-${each.key}"
  description      = "${var.environment}: security and critical patches, approved after ${var.approve_after_days} days"
  operating_system = each.value.operating_system

  approval_rule {
    approve_after_days = var.approve_after_days

    dynamic "patch_filter" {
      for_each = each.value.filters
      content {
        key    = patch_filter.key
        values = patch_filter.value
      }
    }
  }

  tags = { Name = "${var.environment}-${each.key}" }
}

resource "aws_ssm_patch_group" "baselines" {
  for_each = local.baselines

  baseline_id = aws_ssm_patch_baseline.baselines[each.key].id
  patch_group = var.environment
}

resource "aws_cloudwatch_log_group" "patching" {
  name              = "/ssm/patching/${var.environment}"
  retention_in_days = 365

  tags = { Name = "patching-${var.environment}" }
}

resource "aws_ssm_maintenance_window" "patching" {
  name                       = "patching-${var.environment}"
  schedule                   = var.schedule
  duration                   = var.duration_hours
  cutoff                     = 1
  allow_unassociated_targets = false

  tags = { Name = "patching-${var.environment}" }
}

resource "aws_ssm_maintenance_window_target" "instances" {
  window_id     = aws_ssm_maintenance_window.patching.id
  name          = "patch-group-${var.environment}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Patch Group"
    values = [var.environment]
  }
}

# A quarter of the instances at a time, stopping if more than one in ten fail; a reboot only when a patch needs one.
resource "aws_ssm_maintenance_window_task" "install" {
  window_id       = aws_ssm_maintenance_window.patching.id
  name            = "install-patches"
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = "25%"
  max_errors      = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.instances.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds = 3600

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }

      cloudwatch_config {
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patching.name
        cloudwatch_output_enabled = true
      }
    }
  }
}
