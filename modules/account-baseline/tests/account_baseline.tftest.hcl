mock_provider "aws" {}

variables {
  regions = ["us-east-2", "us-west-2"]
}

run "both_regions" {
  command = plan

  assert {
    condition     = aws_s3_account_public_access_block.account.block_public_policy && aws_s3_account_public_access_block.account.restrict_public_buckets
    error_message = "No bucket in the account can be made public."
  }

  assert {
    condition     = toset(keys(aws_ebs_encryption_by_default.regions)) == toset(["us-east-2", "us-west-2"]) && alltrue([for e in aws_ebs_encryption_by_default.regions : e.enabled])
    error_message = "EBS encryption by default in every region."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.regions["us-west-2"].region == "us-west-2" && aws_accessanalyzer_analyzer.regions["us-west-2"].type == "ACCOUNT"
    error_message = "An access analyzer in every region."
  }
}

run "rejects_bad_region" {
  command = plan

  variables {
    regions = ["ohio"]
  }

  expect_failures = [var.regions]
}
