# What the module builds and refuses, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

variables {
  name           = "web"
  log_bucket_arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-2"
  resource_arns  = ["arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/web/abc"]
}

run "defaults" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.web_acl.rule) == 4
    error_message = "Three AWS managed rule groups and a rate limit by default."
  }

  assert {
    condition     = one(aws_wafv2_web_acl_logging_configuration.web_acl.redacted_fields).single_header[0].name == "authorization"
    error_message = "Every request is logged, without the Authorization header."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.resources) == 1
    error_message = "The web ACL protects the load balancers it names."
  }
}

run "cloudfront_scope_attaches_nothing" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.resources) == 0
    error_message = "A distribution names its web ACL; nothing is attached from here."
  }
}

run "rejects_tiny_rate_limit" {
  command = plan

  variables {
    rate_limit = 10
  }

  expect_failures = [var.rate_limit]
}
