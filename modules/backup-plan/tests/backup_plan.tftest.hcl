mock_provider "aws" {
  mock_resource "aws_backup_vault" {
    defaults = { arn = "arn:aws:backup:us-west-2:111111111111:backup-vault:operations-us-west-2" }
  }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "operations"
  backup_vaults = {
    operations = {
      kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-backup"
      lock_configuration = { min_retention_days = 7, max_retention_days = 3650 }
    }
    operations-us-west-2 = {
      region             = "us-west-2"
      kms_key_arn        = "arn:aws:kms:us-west-2:111111111111:key/mrk-backup"
      lock_configuration = { min_retention_days = 7, max_retention_days = 3650 }
    }
  }
  backup_plans = {
    operations = {
      rule = [{
        rule_name         = "daily"
        target_vault_name = "operations"
        schedule          = "cron(0 7 * * ? *)"
        start_window      = 60
        completion_window = 360
        lifecycle         = { delete_after = 35 }
        copy_action       = [{ destination_vault_arn = "operations-us-west-2", lifecycle = { delete_after = 35 } }]
      }]
    }
  }
}

run "daily_copied" {
  command = plan

  assert {
    condition     = aws_backup_vault_lock_configuration.vaults["operations"].min_retention_days == 7 && aws_backup_vault.vaults["operations-us-west-2"].region == "us-west-2" && aws_backup_vault_lock_configuration.vaults["operations-us-west-2"].region == "us-west-2"
    error_message = "Every vault is locked as given, the copy vault in Oregon."
  }

  assert {
    condition     = one(aws_backup_plan.plans["operations"].rule).lifecycle[0].delete_after == 35 && one(aws_backup_plan.plans["operations"].rule).schedule == "cron(0 7 * * ? *)"
    error_message = "The rule is the one given."
  }

  assert {
    condition     = one(aws_backup_selection.tagged["operations"].selection_tag).key == "Backup" && one(aws_backup_selection.tagged["operations"].selection_tag).value == "standard"
    error_message = "Resources join the plan by tagging themselves Backup = standard."
  }
}

run "nothing" {
  command = plan

  variables {
    backup_vaults = {}
    backup_plans  = {}
  }

  assert {
    condition     = length(aws_iam_role.backup) == 0 && length(aws_backup_vault.vaults) == 0
    error_message = "Nothing given, nothing built."
  }
}

run "rejects_a_rule_into_an_unknown_vault" {
  command = plan

  variables {
    backup_plans = { operations = { rule = [{ rule_name = "daily", target_vault_name = "elsewhere" }] } }
  }

  expect_failures = [var.backup_plans]
}
