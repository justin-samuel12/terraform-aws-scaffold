# The state bucket, with and without a replica, against a mocked AWS -- docs/configuration.md.
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::example-terraform-state" }
  }

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

mock_provider "aws" {
  alias = "replica"

  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::example-terraform-state-us-west-2" }
  }
}

variables {
  account_id = "111111111111"
  region     = "us-east-1"
  bucket     = "example-terraform-state"
}

run "single_region" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled" && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "State is versioned and never public."
  }

  assert {
    condition     = length(aws_s3_bucket.replica) == 0 && length(aws_s3_bucket_replication_configuration.state) == 0
    error_message = "No replica unless a replica region is named."
  }
}

run "replicated" {
  command = plan

  variables {
    replica_region = "us-west-2"
  }

  assert {
    condition     = aws_s3_bucket.replica[0].bucket == "example-terraform-state-us-west-2" && length(aws_s3_bucket_replication_configuration.state) == 1
    error_message = "A replica bucket in the second region, with replication from the state bucket."
  }
}

run "rejects_a_bad_name" {
  command = plan

  variables {
    bucket = "Not_A_Bucket"
  }

  expect_failures = [var.bucket]
}

run "other_accounts_reach_only_their_keys" {
  command = plan

  variables {
    account_prefixes = { "222222222222" = ["us-east-2/production/*", "global/production/*"] }
  }

  assert {
    condition     = length(var.account_prefixes["222222222222"]) == 2
    error_message = "Each other account is listed with the key patterns of its own environments."
  }
}

run "rejects_a_bad_account" {
  command = plan

  variables {
    account_prefixes = { "production" = ["us-east-2/production/*"] }
  }

  expect_failures = [var.account_prefixes]
}
