# The region's log buckets, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  region = "us-east-2"
}

run "default_retention" {
  command = plan

  assert {
    condition     = local.buckets["load-balancer"] == "lb-logs-111111111111-us-east-2" && local.buckets.waf == "aws-waf-logs-111111111111-us-east-2"
    error_message = "One bucket for load balancer logs and one for WAF, named by account and region."
  }

  assert {
    condition     = local.settings.retention_days == 365
    error_message = "Without logging.yml, logs are kept a year."
  }
}

run "retention_from_file" {
  command = plan

  variables {
    config_dir = "tests/settings"
  }

  assert {
    condition     = local.settings.retention_days == 400
    error_message = "logging.yml sets the retention."
  }
}
