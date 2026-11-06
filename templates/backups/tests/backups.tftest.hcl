mock_provider "aws" {
  mock_data "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-backup" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "operations" {
  command = plan

  variables {
    config_dir = "tests/operations"
  }

  assert {
    condition     = toset(keys(local.vaults)) == toset(["operations", "operations-us-west-2"]) && local.vaults["operations-us-west-2"].region == "us-west-2" && length(local.problems) == 0
    error_message = "One vault per file, named after it, in the region it names."
  }

  assert {
    condition     = jsonencode([for r in local.plans.operations.rule : [r.rule_name, r.lifecycle.delete_after, r.copy_action[0].destination_vault_arn]]) == jsonencode([["daily", 35, "operations-us-west-2"], ["monthly", 365, "operations-us-west-2"]])
    error_message = "The plan's rules as written: daily and monthly, each copied to Oregon."
  }

  assert {
    condition     = toset(keys(local.key_names)) == toset(["operations", "operations-us-west-2"]) && local.vaults.operations.lock_configuration.changeable_for_days == null
    error_message = "A key named by alias is looked up in its vault's region; the lock is governance unless the file says otherwise."
  }
}

run "nothing" {
  command = plan

  assert {
    condition     = output.vaults == {} && output.plans == {}
    error_message = "Without files, no vaults and no plans."
  }
}

run "refusals" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([for p in [
      "settings/backups.yml: files go in backup-vault/ or backup-plan/",
      "backup-vault/unlocked.yml: keys are region, kms_key_arn, lock_configuration, tags",
      "backup-vault/unlocked.yml: needs lock_configuration",
      "backup-plan/operations.yml: rule hourly keeps backups in operations 3 days, outside its lock (7 to 3650 days)",
      "backup-plan/operations.yml: rule daily: destination_vault_arn elsewhere is not a vault in this stack",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "An old settings file, a vault without a lock, a retention the lock refuses and a copy to an unknown vault are each refused."
  }

  expect_failures = [output.vaults]
}
