mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_elb_service_account.current
  values = { arn = "arn:aws:iam::033677994240:root" }
}

variables {
  name     = "lb-logs-111111111111-us-east-2"
  delivers = "load-balancer"
}

run "load_balancer_logs" {
  command = plan

  assert {
    condition     = jsondecode(local.policy).Statement[0].Sid == "DenyInsecureTransport" && length(jsondecode(local.policy).Statement) == 3
    error_message = "TLS only, then both load balancer delivery principals."
  }

  assert {
    condition     = aws_s3_bucket_versioning.logs.versioning_configuration[0].status == "Enabled" && aws_s3_bucket_ownership_controls.logs.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Versioned, and no ACLs: the account owns every object."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.logs) == 0
    error_message = "Without rules, no lifecycle: nothing expires that a file does not say."
  }
}

run "lifecycle_rules" {
  command = plan

  variables {
    rule = [{
      id                                = "retention"
      status                            = "Enabled"
      expiration                        = { days = 400 }
      noncurrent_version_expiration     = { noncurrent_days = 30 }
      abort_incomplete_multipart_upload = { days_after_initiation = 7 }
    }]
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.logs[0].rule[0].expiration[0].days == 400 && aws_s3_bucket_lifecycle_configuration.logs[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "The rules are the ones given."
  }
}

run "rejects_an_unknown_status" {
  command = plan

  variables {
    rule = [{ id = "retention", status = "On", expiration = { days = 400 } }]
  }

  expect_failures = [var.rule]
}

run "waf_logs" {
  command = plan

  variables {
    name     = "aws-waf-logs-111111111111-us-east-2"
    delivers = "waf"
  }

  assert {
    condition     = contains([for s in jsondecode(local.policy).Statement : s.Sid], "WafLogDelivery")
    error_message = "WAF delivers through the log delivery service, for this account only."
  }
}

run "rejects_waf_bucket_without_prefix" {
  command = plan

  variables {
    name     = "waf-logs-111111111111-us-east-2"
    delivers = "waf"
  }

  expect_failures = [aws_s3_bucket.logs]
}
