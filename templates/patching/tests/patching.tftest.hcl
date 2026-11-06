mock_provider "aws" {}

variables {
  environment = "operations"
}

run "baselines_and_window" {
  command = plan

  variables {
    config_dir = "tests/baselines"
  }

  assert {
    condition     = toset(keys(local.patch_baselines)) == toset(["windows", "amazon-linux-2023", "ubuntu"]) && length(local.problems) == 0 && output.patch_group == "operations"
    error_message = "One baseline per file; instances tagged PatchGroup = operations are patched."
  }

  assert {
    condition     = local.patch_baselines.windows.approval_rule[0].approve_after_days == 7 && jsonencode(local.patch_baselines.windows.approval_rule[0].patch_filter[0]) == jsonencode({ key = "CLASSIFICATION", values = ["SecurityUpdates", "CriticalUpdates"] })
    error_message = "An approval rule is the file's own."
  }

  assert {
    condition     = local.maintenance_windows.patching.schedule == "cron(0 7 ? * SUN *)" && local.maintenance_windows.patching.cutoff == 1 && local.maintenance_windows.patching.schedule_timezone == null
    error_message = "The window as its file gives it, and nothing it does not."
  }
}

run "nothing" {
  command = plan

  assert {
    condition     = local.patch_baselines == {} && local.maintenance_windows == {}
    error_message = "Without files, no baselines and no window."
  }
}

run "refusals" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([for p in [
      "settings/patching.yml: files go in patch-baseline/ or maintenance-window/",
      "patch-baseline/windows.yml: keys are description, operating_system",
      "patch-baseline/: windows-server.yml, windows.yml are all for WINDOWS",
      "maintenance-window/patching.yml: needs cutoff",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "An old settings file, a key that is not an argument, two baselines for one system and a window without cutoff are each refused."
  }

  expect_failures = [output.patch_group]
}
