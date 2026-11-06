resource "aws_ssm_patch_baseline" "baselines" {
  for_each = var.patch_baselines

  name             = "${var.environment}-${each.key}"
  description      = each.value.description
  operating_system = each.value.operating_system
  approved_patches = each.value.approved_patches
  rejected_patches = each.value.rejected_patches

  dynamic "approval_rule" {
    for_each = each.value.approval_rule
    content {
      approve_after_days  = approval_rule.value.approve_after_days
      compliance_level    = approval_rule.value.compliance_level
      enable_non_security = approval_rule.value.enable_non_security

      dynamic "patch_filter" {
        for_each = approval_rule.value.patch_filter
        content {
          key    = patch_filter.value.key
          values = patch_filter.value.values
        }
      }
    }
  }

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${each.key}" })
}

resource "aws_ssm_patch_group" "baselines" {
  for_each = var.patch_baselines

  baseline_id = aws_ssm_patch_baseline.baselines[each.key].id
  patch_group = var.environment
}

resource "aws_cloudwatch_log_group" "patching" {
  count = length(var.maintenance_windows) > 0 ? 1 : 0

  name              = "/ssm/patching/${var.environment}"
  retention_in_days = 365

  tags = { Name = "${local.name_prefix}patching" }
}

resource "aws_ssm_maintenance_window" "windows" {
  for_each = var.maintenance_windows

  name                       = "${var.environment}-${each.key}"
  description                = each.value.description
  schedule                   = each.value.schedule
  schedule_timezone          = each.value.schedule_timezone
  duration                   = each.value.duration
  cutoff                     = each.value.cutoff
  enabled                    = each.value.enabled
  allow_unassociated_targets = false

  tags = merge(each.value.tags, { Name = "${local.name_prefix}${each.key}" })
}

resource "aws_ssm_maintenance_window_target" "instances" {
  for_each = var.maintenance_windows

  window_id     = aws_ssm_maintenance_window.windows[each.key].id
  name          = "patch-group-${var.environment}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = [var.environment]
  }
}

resource "aws_ssm_maintenance_window_task" "install" {
  for_each = var.maintenance_windows

  window_id       = aws_ssm_maintenance_window.windows[each.key].id
  name            = "install-patches"
  task_type       = "RUN_COMMAND"
  task_arn        = "AWS-RunPatchBaseline"
  priority        = 1
  max_concurrency = "25%"
  max_errors      = "10%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.instances[each.key].id]
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
        cloudwatch_log_group_name = aws_cloudwatch_log_group.patching[0].name
        cloudwatch_output_enabled = true
      }
    }
  }
}
