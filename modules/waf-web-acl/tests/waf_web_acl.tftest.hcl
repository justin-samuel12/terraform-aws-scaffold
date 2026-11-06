mock_provider "aws" {}

variables {
  name              = "web"
  scope             = "REGIONAL"
  default_action    = { allow = {} }
  visibility_config = { cloudwatch_metrics_enabled = true, metric_name = "web", sampled_requests_enabled = true }
  rule = [
    {
      name              = "rate-limit"
      priority          = 0
      action            = { block = {} }
      statement         = { rate_based_statement = { limit = 2000, aggregate_key_type = "IP" } }
      visibility_config = { cloudwatch_metrics_enabled = true, metric_name = "web-rate-limit", sampled_requests_enabled = true }
    },
    {
      name              = "AWSManagedRulesCommonRuleSet"
      priority          = 1
      override_action   = { none = {} }
      statement         = { managed_rule_group_statement = { name = "AWSManagedRulesCommonRuleSet", vendor_name = "AWS" } }
      visibility_config = { cloudwatch_metrics_enabled = true, metric_name = "web-AWSManagedRulesCommonRuleSet", sampled_requests_enabled = true }
    },
  ]
  log_bucket_arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-2"
  resource_arns  = ["arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/web/abc"]
}

run "web" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.web_acl.rule) == 2 && length(one(aws_wafv2_web_acl.web_acl.default_action).allow) == 1 && length(one(aws_wafv2_web_acl.web_acl.default_action).block) == 0
    error_message = "The web ACL has the rules it was given and allows what none of them blocks."
  }

  assert {
    condition     = toset([for r in aws_wafv2_web_acl.web_acl.rule : r.name]) == toset(["rate-limit", "AWSManagedRulesCommonRuleSet"])
    error_message = "Each rule keeps its name."
  }

  assert {
    condition     = toset([for f in aws_wafv2_web_acl_logging_configuration.web_acl.redacted_fields : f.single_header[0].name]) == toset(["authorization", "cookie"])
    error_message = "Every request is logged, without the Authorization or Cookie header."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.resources) == 1
    error_message = "The web ACL protects the load balancers it names."
  }
}

run "cloudfront_scope_attaches_nothing" {
  command = plan

  variables {
    scope         = "CLOUDFRONT"
    resource_arns = []
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.resources) == 0 && aws_wafv2_web_acl.web_acl.scope == "CLOUDFRONT"
    error_message = "A distribution names its web ACL; nothing is attached from here."
  }
}

run "rejects_resources_on_a_cloudfront_acl" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
  }

  expect_failures = [var.resource_arns]
}

run "rejects_tiny_rate_limit" {
  command = plan

  variables {
    rule = [
      {
        name              = "rate-limit"
        priority          = 0
        action            = { block = {} }
        statement         = { rate_based_statement = { limit = 10, aggregate_key_type = "IP" } }
        visibility_config = { cloudwatch_metrics_enabled = true, metric_name = "web-rate-limit", sampled_requests_enabled = true }
      },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_an_action_on_a_managed_rule_group" {
  command = plan

  variables {
    rule = [
      {
        name              = "AWSManagedRulesCommonRuleSet"
        priority          = 1
        action            = { block = {} }
        statement         = { managed_rule_group_statement = { name = "AWSManagedRulesCommonRuleSet", vendor_name = "AWS" } }
        visibility_config = { cloudwatch_metrics_enabled = true, metric_name = "web-common", sampled_requests_enabled = true }
      },
    ]
  }

  expect_failures = [var.rule]
}

run "rejects_allow_and_block" {
  command = plan

  variables {
    default_action = { allow = {}, block = {} }
  }

  expect_failures = [var.default_action]
}
