# Bucket files turned into buckets, against a mocked AWS -- docs/data.md.
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
    condition     = local.names.reports == "production-reports-111111111111-us-east-2" && toset(keys(output.buckets)) == toset(["reports", "records"])
    error_message = "One bucket per file, named <environment>-<file>-<account>-<region>."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.buckets == {}
    error_message = "Without files, no buckets."
  }
}
