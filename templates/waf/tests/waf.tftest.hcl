mock_provider "aws" {}

override_data {
  target = data.aws_s3_bucket.logs[0]
  values = { arn = "arn:aws:s3:::aws-waf-logs-111111111111-us-east-2" }
}

override_data {
  target = data.aws_lb.load_balancers["web"]
  values = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/web/abc" }
}

variables {
  environment = "operations"
  region      = "us-east-2"
}

run "web" {
  command = plan

  variables {
    config_dir = "tests/acls"
  }

  assert {
    condition     = length(local.problems) == 0 && toset(keys(output.arns)) == toset(["web"])
    error_message = "One web ACL per file."
  }

  assert {
    condition     = local.web_acls.web.rule[0].statement.rate_based_statement.limit == 1000 && local.web_acls.web.rule[0].action.block != null && local.web_acls.web.rule[1].override_action.none != null && local.web_acls.web.default_action.allow != null
    error_message = "A web ACL is its file's rules and default_action, as written."
  }

  assert {
    condition     = toset(local.resource_arns.web) == toset(["arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/web/abc", "arn:aws:elasticloadbalancing:us-east-2:111111111111:loadbalancer/app/other/def"])
    error_message = "resource_arns names a load balancer of this environment, found by name; an ARN passes through."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "web.yml: keys are default_action, rule, visibility_config, resource_arns, as aws_wafv2_web_acl takes them (resource_arns: the load balancers it protects)"),
      contains(local.problems, "web.yml: default_action is allow or block"),
      contains(local.problems, "web.yml: the rule common needs name, priority and visibility_config (cloudwatch_metrics_enabled, metric_name, sampled_requests_enabled)"),
      contains(local.problems, "web.yml: statement in the rule common is managed_rule_group_statement (name, vendor_name) or rate_based_statement (limit, aggregate_key_type)"),
    ])
    error_message = "managed_rules, rate_limit and load_balancers are not arguments, and nothing is filled in for a file."
  }

  expect_failures = [output.arns]
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without files, no web ACLs."
  }
}
