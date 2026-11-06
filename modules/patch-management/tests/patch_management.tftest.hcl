mock_provider "aws" {}

variables {
  environment = "production"
  patch_baselines = {
    windows = {
      operating_system = "WINDOWS"
      approval_rule = [{
        approve_after_days = 7
        patch_filter = [
          { key = "CLASSIFICATION", values = ["SecurityUpdates", "CriticalUpdates"] },
          { key = "MSRC_SEVERITY", values = ["Critical", "Important"] },
        ]
      }]
    }
    ubuntu = {
      operating_system = "UBUNTU"
      approval_rule    = [{ approve_after_days = 7, patch_filter = [{ key = "PRIORITY", values = ["Required", "Important"] }] }]
    }
  }
  maintenance_windows = {
    patching = { schedule = "cron(0 7 ? * SUN *)", duration = 3, cutoff = 1 }
  }
}

run "production" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssm_patch_baseline.baselines)) == toset(["windows", "ubuntu"]) && aws_ssm_patch_baseline.baselines["windows"].name == "production-windows" && alltrue([for p in aws_ssm_patch_group.baselines : p.patch_group == "production"])
    error_message = "A baseline per file, each for the environment's patch group."
  }

  assert {
    condition     = aws_ssm_patch_baseline.baselines["windows"].approval_rule[0].approve_after_days == 7 && length(aws_ssm_patch_baseline.baselines["windows"].approval_rule[0].patch_filter) == 2
    error_message = "The approval rule is the one given."
  }

  assert {
    condition     = aws_ssm_maintenance_window.windows["patching"].name == "production-patching" && aws_ssm_maintenance_window.windows["patching"].cutoff == 1
    error_message = "The window as given."
  }

  assert {
    condition     = one(aws_ssm_maintenance_window_target.instances["patching"].targets).key == "tag:PatchGroup" && aws_ssm_maintenance_window_task.install["patching"].max_concurrency == "25%"
    error_message = "Instances tagged PatchGroup = production are patched a quarter at a time."
  }
}

run "nothing" {
  command = plan

  variables {
    patch_baselines     = {}
    maintenance_windows = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.patching) == 0 && length(aws_ssm_patch_baseline.baselines) == 0
    error_message = "Nothing given, nothing built."
  }
}

run "rejects_a_free_schedule" {
  command = plan

  variables {
    maintenance_windows = { patching = { schedule = "every sunday", duration = 3, cutoff = 1 } }
  }

  expect_failures = [var.maintenance_windows]
}

run "rejects_two_baselines_for_one_system" {
  command = plan

  variables {
    patch_baselines = {
      windows   = { operating_system = "WINDOWS" }
      windows-2 = { operating_system = "WINDOWS" }
    }
  }

  expect_failures = [var.patch_baselines]
}
