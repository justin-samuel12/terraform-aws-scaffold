# The environment's backup plan, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_kms_key.backup
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-backup" }
}

override_data {
  target = data.aws_kms_key.backup_copy[0]
  values = { arn = "arn:aws:kms:us-west-2:111111111111:key/mrk-backup" }
}

override_data {
  target = module.backup_plan.data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  config_path = "../../tests/config"
}

run "operations" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
  }

  assert {
    condition     = output.copy_region == "us-west-2" && local.settings.daily_retention_days == 35
    error_message = "Daily backups kept 35 days, copied to Oregon."
  }
}
