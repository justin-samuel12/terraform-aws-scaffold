mock_provider "aws" {}

override_data {
  target = module.kms_key.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.kms_key.data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.kms_key.data.aws_region.current
  values = { region = "us-east-2" }
}

override_data {
  target = module.session_manager_preferences.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.session_manager_preferences.data.aws_region.current
  values = { region = "us-east-2" }
}

override_data {
  target = module.session_manager_preferences.data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  config_path = "../../tests/config"
}

run "preferences" {
  command = plan

  variables {
    environment = "shared"
    region      = "us-east-2"
    config_dir  = "tests/preferences"
  }

  assert {
    condition     = jsonencode(local.document.content.inputs) == jsonencode({ idleSessionTimeout = "20", maxSessionDuration = "480" }) && output.log_group == "/ssm/sessions"
    error_message = "Sessions close after the file's idle timeout and length, and are logged."
  }

  assert {
    condition     = local.log_group_args.retention_in_days == 365
    error_message = "The log group keeps sessions as long as its file says."
  }
}

run "nothing" {
  command = plan

  variables {
    environment = "shared"
    region      = "us-east-2"
  }

  assert {
    condition     = local.document == null && local.log_group_args == null && output.log_group == null
    error_message = "Without files, no document and no log group; the key and Default Host Management stay."
  }
}

run "refuses_preferences_without_their_log_group" {
  command = plan

  variables {
    environment = "shared"
    region      = "us-east-2"
    config_dir  = "tests/no-log-group"
  }

  assert {
    condition     = contains(local.problems, "document/SSM-SessionManagerRunShell.yml streams every session to /ssm/sessions: add log-group/sessions.yml")
    error_message = "Preferences without the log group they stream to are refused."
  }

  expect_failures = [output.log_group]
}

run "refusals" {
  command = plan

  variables {
    environment = "shared"
    region      = "us-east-2"
    config_dir  = "tests/refused"
  }

  assert {
    condition = alltrue([for p in [
      "settings/session-manager.yml: files go in document/ or log-group/",
      "document/SSM-SessionManagerRunShell.yml: keys are content, tags",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "An old settings file and an input that is fixed are each refused."
  }

  expect_failures = [output.log_group]
}
