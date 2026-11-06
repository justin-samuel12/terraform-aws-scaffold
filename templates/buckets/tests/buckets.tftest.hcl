mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

variables {
  environment = "production"
  region      = "us-east-2"
}

run "two_buckets" {
  command = plan

  variables {
    config_dir = "tests/buckets"
  }

  assert {
    condition     = local.names.reports == "production-reports-111111111111-us-east-2" && toset(keys(output.buckets)) == toset(["reports", "records"]) && length(local.problems) == 0
    error_message = "One bucket per file, named <environment>-<file>-<account>-<region>."
  }

  assert {
    condition     = local.buckets.reports.tags.Backup == "standard" && length(local.buckets.records.tags) == 0
    error_message = "Backup is a tag the file writes."
  }

  assert {
    condition     = jsonencode(local.buckets.reports.lifecycle_rule[0]) == jsonencode({ id = "reports", status = "Enabled", filter = null, expiration = { days = 400 }, noncurrent_version_expiration = { noncurrent_days = 90 }, abort_incomplete_multipart_upload = { days_after_initiation = 7 } })
    error_message = "A lifecycle rule is what the file writes."
  }

  assert {
    condition     = local.buckets.records.object_lock_enabled && local.buckets.records.object_lock_configuration.rule.default_retention.days == 2555 && length(local.buckets.records.cors_rule) == 0
    error_message = "Object lock in the provider's shape; no CORS unless written."
  }

  assert {
    condition     = jsonencode(local.buckets.reports.cors_rule) == jsonencode([{ id = null, allowed_methods = ["GET"], allowed_origins = ["https://reports.example.com"], allowed_headers = null, expose_headers = null, max_age_seconds = null }])
    error_message = "A cors_rule has only what it writes."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.buckets == {}
    error_message = "Without files, no buckets."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "reports.yml: keys are tags, object_lock_enabled, object_lock_configuration, lifecycle_configuration, cors_rule, as aws_s3_bucket and its configuration resources take them")
    error_message = "backup: and expiration: are not arguments."
  }

  expect_failures = [output.buckets]
}
