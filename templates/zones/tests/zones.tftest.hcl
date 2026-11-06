mock_provider "aws" {
  mock_resource "aws_route53_zone" {
    defaults = { zone_id = "Z0ENVIRONMENT" }
  }
}

mock_provider "aws" {
  alias = "hub"
}

variables {
  config_path = "../../tests/config"
}

run "an_environments_private_zone" {
  command = plan

  variables {
    environment = "staging"
  }

  assert {
    condition     = aws_route53_zone.private[0].name == "staging.corp.internal" && one(aws_route53_zone.private[0].vpc).vpc_region == "us-west-2"
    error_message = "Its private zone, <environment>.<private_domain>, attached to its VPC."
  }

  assert {
    condition     = toset(keys(aws_route53_zone_association.hubs)) == toset(["us-east-2", "us-west-2"]) && length(aws_route53_vpc_association_authorization.hubs) == 0
    error_message = "Its private zone is attached to every region's hub VPC, so the hubs' resolvers answer for it; one account, so no authorization is needed."
  }
}

run "refuses_the_hubs" {
  command = plan

  variables {
    environment = "shared"
  }

  expect_failures = [var.environment]
}

run "a_hub_in_another_account" {
  command = plan

  variables {
    environment = "staging"
    config_path = "../../templates/dns/tests/accounts"
  }

  assert {
    condition     = toset(keys(aws_route53_vpc_association_authorization.hubs)) == toset(["us-east-2", "us-west-2"]) && toset(keys(aws_route53_zone_association.hubs_from_hub)) == toset(["us-east-2", "us-west-2"]) && length(aws_route53_zone_association.hubs) == 0
    error_message = "Across accounts, the zone's owner authorizes each hub VPC and the hub attaches it, as the network stack does for the hub's own private zones."
  }
}
