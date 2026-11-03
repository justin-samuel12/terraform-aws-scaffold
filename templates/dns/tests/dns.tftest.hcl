# zones.yml and config's private zones turned into hosted zones, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "public_zones" {
  command = plan

  variables {
    config_dir = "tests/zones"
  }

  assert {
    condition     = local.public == toset(["example.com"]) && toset(keys(output.public)) == toset(["example.com"])
    error_message = "One public zone per name in zones.yml."
  }

  assert {
    condition     = output.private == {}
    error_message = "No private zones until config/global.yml lists them."
  }
}

run "every_hub_joins_the_private_zones" {
  command = plan

  variables {
    config_path = "../../templates/dns/tests/two-hubs"
  }

  assert {
    condition     = toset(keys(output.private)) == toset(["internal.example.com"]) && local.other_hubs == tolist(["us-west-2"])
    error_message = "The private zone is created with the primary hub, in us-east-2."
  }

  assert {
    condition     = toset(keys(aws_route53_zone_association.other_hubs)) == toset(["internal.example.com us-west-2"]) && aws_route53_zone_association.other_hubs["internal.example.com us-west-2"].vpc_region == "us-west-2"
    error_message = "This stack associates the Oregon hub, so no hub has to wait for it."
  }
}

run "a_hub_in_another_account" {
  command = plan

  variables {
    config_path = "../../templates/dns/tests/foreign-hub"
  }

  assert {
    condition     = local.foreign_hubs == ["us-west-2"] && length(aws_route53_zone_association.other_hubs) == 0
    error_message = "A hub outside the primary hub's account is not associated from here."
  }

  expect_failures = [output.private]
}
