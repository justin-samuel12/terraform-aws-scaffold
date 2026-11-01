# The stack's own job: identity from its path and its region file, passed to templates/network -- docs/network.md.
mock_provider "aws" {}

override_data {
  target = module.network.data.aws_route53_resolver_rules.hub
  values = { resolver_rule_ids = ["rslvr-rr-ad"] }
}

override_data {
  target = module.network.module.vpc.data.aws_availability_zones.available
  values = { zone_ids = ["use1-az1", "use1-az2", "use1-az4"] }
}

variables {
  config_dir  = "../../../../tests/stacks"
  config_file = "/nonexistent"
}

run "development" {
  command = plan

  assert {
    condition     = local.environment == "development" && local.region == "us-east-1" && local.component == "network"
    error_message = "The stack reads its identity from its path."
  }

  assert {
    condition     = local.account_id == "222222222222" && local.team == "platform" && local.pinned
    error_message = "The stack takes its account and team from vpcs.development in its region file."
  }

  assert {
    condition     = output.network.network.cidr == "10.41.0.0/16"
    error_message = "The stack builds templates/network for development."
  }
}

run "refuses_without_an_account" {
  command = plan

  # No account or team yet: nothing may run, and the missing team warns.
  variables {
    config_dir = "../../../../tests/unset"
  }

  expect_failures = [data.aws_caller_identity.current, check.team_set]
}
