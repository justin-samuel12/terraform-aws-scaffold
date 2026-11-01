# The region's Session Manager preferences, against a mocked AWS -- docs/systems-manager.md.
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

run "defaults" {
  command = plan

  variables {
    environment = "shared"
    region      = "us-east-2"
  }

  assert {
    condition     = local.settings.idle_timeout_minutes == 20 && output.log_group == "/ssm/sessions"
    error_message = "Sessions close after 20 idle minutes and are logged."
  }

  assert {
    condition     = length(module.session_manager_preferences) == 1
    error_message = "Ohio, the primary region, creates the Default Host Management role."
  }
}
