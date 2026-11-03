# What the module builds and refuses, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

variables {
  environment        = "production"
  approve_after_days = 7
}

run "production" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssm_patch_baseline.baselines)) == toset(["windows", "amazon-linux-2023", "ubuntu"]) && alltrue([for p in aws_ssm_patch_group.baselines : p.patch_group == "production"])
    error_message = "A baseline per operating system, each for the environment's patch group."
  }

  assert {
    condition     = one(aws_ssm_maintenance_window_target.instances.targets).key == "tag:PatchGroup" && aws_ssm_maintenance_window_task.install.max_concurrency == "25%"
    error_message = "Instances tagged PatchGroup = production are patched a quarter at a time."
  }
}

run "rejects_cron_free_schedule" {
  command = plan

  variables {
    schedule = "rate(7 days)"
  }

  expect_failures = [var.schedule]
}
