mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "public_zones" {
  command = plan

  assert {
    condition     = local.public == toset(["example.com"]) && toset(keys(output.public)) == toset(["example.com"])
    error_message = "One public zone per domain in dns.public_domain."
  }

  assert {
    condition     = toset(keys(output.private)) == toset(["corp.internal"])
    error_message = "The private domain is a zone in the hub, made here like the zones in dns.private_zones."
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

run "each_environment_writes_only_its_own_names" {
  command = plan

  variables {
    config_path = "../../templates/dns/tests/accounts"
  }

  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }

  assert {
    condition     = toset(keys(aws_iam_role.dns_writer)) == toset(["staging", "production"])
    error_message = "A role for each environment in another account than the domain's; operations shares the hub's account, so it needs none."
  }

  assert {
    condition     = jsonencode(local.writers.staging.names) == jsonencode(["example.com", "*.example.com", "example.org", "*.example.org"]) && local.writers.production.names == local.writers.staging.names
    error_message = "Every environment writes its names in every public domain."
  }

  assert {
    condition     = toset(keys(output.public)) == toset(["example.com", "example.org"])
    error_message = "Every public domain is a zone in the hub."
  }

  assert {
    condition     = jsondecode(aws_iam_role.dns_writer["staging"].assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::222222222222:root"
    error_message = "Only staging's account can take staging's role."
  }
}
