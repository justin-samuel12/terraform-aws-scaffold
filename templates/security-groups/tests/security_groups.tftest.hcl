# Group files turned into rules, against a mocked AWS -- docs/security-groups.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-development" }
}

variables {
  config_path = "../../tests/config"
  environment = "development"
  region      = "us-east-2"
}

run "development" {
  command = plan

  variables {
    config_dir = "tests/groups"
  }

  assert {
    condition     = toset(keys(local.groups)) == toset(["grafana", "grafana-lb"])
    error_message = "One group per file, named after the file."
  }

  assert {
    condition     = length([for r in local.groups.grafana.ingress : r if r.from_port == 22]) == 3 && contains([for r in local.groups.grafana.ingress : r.cidr], "10.42.228.0/23")
    error_message = "tier:ops stands for development' three ops subnets."
  }

  assert {
    condition     = length([for r in local.groups.grafana.ingress : r if r.group == "self"]) == 2 && contains([for r in local.groups.grafana.ingress : r.to_port], 9110)
    error_message = "A port and a range each become a rule."
  }

  assert {
    condition     = local.groups["grafana-lb"].ingress[0].cidr == "10.41.0.0/16"
    error_message = "network:production stands for production's VPC in the same region."
  }

  assert {
    condition     = local.groups.grafana.egress == null && length(local.groups["grafana-lb"].egress) == 1
    error_message = "Egress is the module's default unless a file sets its own."
  }
}

run "refuses_a_tier_the_vpc_lacks" {
  command = plan

  variables {
    config_dir = "tests/bad-tier"
  }

  expect_failures = [output.ids]
}

run "refuses_a_list_config_does_not_have" {
  command = plan

  # config/global.yml has no prefix lists yet, so list:staff-team has nothing to stand for.
  variables {
    config_dir = "tests/unknown-list"
  }

  expect_failures = [output.ids]
}
