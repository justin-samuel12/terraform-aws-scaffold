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
  document    = { content = { inputs = { idleSessionTimeout = "20", maxSessionDuration = "480" } } }
  log_group   = { retention_in_days = 365 }
}

run "preferences" {
  command = plan

  assert {
    condition     = aws_ssm_document.preferences[0].name == "SSM-SessionManagerRunShell" && jsondecode(aws_ssm_document.preferences[0].content).inputs.idleSessionTimeout == "20"
    error_message = "Sessions are encrypted, logged, and closed after 20 idle minutes."
  }

  assert {
    condition     = aws_cloudwatch_log_group.sessions[0].retention_in_days == 365
    error_message = "Session logs are kept as long as the log group says."
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

run "nothing_but_default_host_management" {
  command = plan

  variables {
    document  = null
    log_group = null
  }

  assert {
    condition     = length(aws_ssm_document.preferences) == 0 && length(aws_cloudwatch_log_group.sessions) == 0 && output.log_group == null
    error_message = "Without a document or a log group, neither is built."
  }
}

run "rejects_long_idle" {
  command = plan

  variables {
    document = { content = { inputs = { idleSessionTimeout = "240", maxSessionDuration = "480" } } }
  }

  expect_failures = [var.document]
}

run "rejects_preferences_without_their_log_group" {
  command = plan

  variables {
    log_group = null
  }

  expect_failures = [aws_ssm_document.preferences]
}
