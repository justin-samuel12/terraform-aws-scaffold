# What the module builds and refuses, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "development"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-backup"
  copy        = { region = "us-west-2", kms_key_arn = "arn:aws:kms:us-west-2:111111111111:key/mrk-backup" }
}

run "daily_monthly_copied" {
  command = plan

  assert {
    condition     = aws_backup_vault_lock_configuration.vault.min_retention_days == 7 && aws_backup_vault.copy[0].region == "us-west-2"
    error_message = "A locked vault here, and a locked copy vault in Oregon."
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.copy[0].min_retention_days == 7 && aws_backup_plan.plan.name == "development"
    error_message = "The Oregon copies are locked like the originals."
  }

  assert {
    condition     = one(aws_backup_selection.tagged.selection_tag).key == "Backup" && one(aws_backup_selection.tagged.selection_tag).value == "standard"
    error_message = "Resources join the plan by tagging themselves Backup = standard."
  }
}

run "rejects_short_retention" {
  command = plan

  variables {
    daily_retention_days = 3
  }

  expect_failures = [var.daily_retention_days]
}
