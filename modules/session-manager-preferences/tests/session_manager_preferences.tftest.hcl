# What the module builds and refuses, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-sessions"
}

run "preferences" {
  command = plan

  assert {
    condition     = aws_ssm_document.preferences.name == "SSM-SessionManagerRunShell" && jsondecode(aws_ssm_document.preferences.content).inputs.idleSessionTimeout == "20"
    error_message = "Sessions are encrypted, logged, and closed after 20 idle minutes."
  }

  assert {
    condition     = aws_cloudwatch_log_group.sessions.retention_in_days == 365
    error_message = "Session logs are kept a year."
  }

  assert {
    condition     = endswith(aws_ssm_service_setting.default_host.setting_id, "servicesetting/ssm/managed-instance/default-ec2-instance-management-role") && length(aws_iam_role.default_host) == 0
    error_message = "Every region turns on Default Host Management; only the primary creates the role."
  }
}

run "primary_creates_the_role" {
  command = plan

  variables {
    create_default_host_role = true
  }

  assert {
    condition     = aws_iam_role.default_host[0].name == "AWSSystemsManagerDefaultEC2InstanceManagementRole" && aws_iam_role.default_host[0].path == "/service-role/"
    error_message = "The primary region creates the account's Default Host Management role."
  }
}

run "rejects_long_idle" {
  command = plan

  variables {
    idle_timeout_minutes = 240
  }

  expect_failures = [var.idle_timeout_minutes]
}
