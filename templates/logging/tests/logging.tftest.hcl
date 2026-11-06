mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  region = "us-east-2"
}

run "buckets" {
  command = plan

  variables {
    config_dir = "tests/buckets"
  }

  assert {
    condition     = local.buckets["lb-logs"].bucket == "lb-logs-111111111111-us-east-2" && local.buckets["aws-waf-logs"].bucket == "aws-waf-logs-111111111111-us-east-2" && length(local.problems) == 0
    error_message = "One bucket per file, named by the file, the account and the region."
  }

  assert {
    condition     = local.buckets["lb-logs"].delivers == "load-balancer" && local.buckets["aws-waf-logs"].delivers == "waf"
    error_message = "Which service delivers follows from which bucket it is."
  }

  assert {
    condition     = local.buckets["lb-logs"].rule[0].expiration.days == 400 && length(local.buckets["aws-waf-logs"].rule) == 0
    error_message = "Lifecycle rules are the file's own; a file without any keeps its logs."
  }
}

run "nothing" {
  command = plan

  assert {
    condition     = output.buckets == {}
    error_message = "Without files, no buckets."
  }
}

run "refusals" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([for p in [
      "logging.yml: a log bucket is lb-logs (load balancer access logs) or aws-waf-logs",
      "lb-logs.yml: keys are tags, lifecycle_configuration",
      "cloudtrail.yml: a log bucket is lb-logs (load balancer access logs) or aws-waf-logs",
      "cloudtrail.yml: a lifecycle rule takes id, status",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "An old settings file, a key that is not an argument, an unknown bucket and an unsupported rule key are each refused."
  }

  expect_failures = [output.buckets]
}
