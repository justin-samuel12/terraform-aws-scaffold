# The stack's own job: identity from its path and its region file, passed to templates/hub -- docs/network.md.
mock_provider "aws" {}

override_data {
  target = module.hub.module.vpc.data.aws_availability_zones.available
  values = { zone_ids = ["use1-az1", "use1-az2", "use1-az4"] }
}

variables {
  config_dir  = "../../../../tests/stacks"
  config_file = "/nonexistent"
}

run "hub" {
  command = plan

  assert {
    condition     = local.environment == "shared" && local.region == "us-east-1" && local.component == "hub"
    error_message = "The stack reads its identity from its path."
  }

  assert {
    condition     = local.account_id == "111111111111" && local.team == "platform"
    error_message = "The hub takes its account and team from hub in its region file."
  }

  assert {
    condition     = output.hub.network.cidr == "10.40.0.0/20" && output.hub.network.amazon_side_asn == 64512
    error_message = "The stack builds templates/hub for its region."
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
