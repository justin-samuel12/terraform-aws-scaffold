# Group files turned into rules, against a mocked AWS -- docs/security-groups.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-operations" }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "operations" {
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
    error_message = "tier:ops stands for operations' three ops subnets."
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

run "refuses_a_remote_group_while_referencing_is_off" {
  command = plan

  variables {
    environment = "production"
    config_dir  = "tests/remote"
  }

  expect_failures = [output.ids]
}

run "remote_group_with_referencing_on" {
  command = plan

  variables {
    environment = "production"
    config_dir  = "tests/remote"
    config_path = "../../templates/security-groups/tests/referencing-on"
  }

  override_data {
    target = data.aws_security_group.remote["operations/monitoring"]
    values = { id = "sg-operations-monitoring" }
  }

  assert {
    condition     = local.groups["monitoring-agent"].ingress[0].remote_group == "operations/monitoring" && local.groups["monitoring-agent"].ingress[0].remote_group_id == "sg-operations-monitoring"
    error_message = "group:<environment>/<group> references that environment's group, found by its tags."
  }
}

run "refuses_its_own_environment_named_the_long_way" {
  command = plan

  variables {
    environment = "production"
    config_dir  = "tests/own-remote"
    config_path = "../../templates/security-groups/tests/referencing-on"
  }

  expect_failures = [output.ids]
}

run "refuses_a_rule_without_from_port_and_to_port" {
  command = plan

  variables {
    config_dir = "tests/shortcut"
  }

  expect_failures = [output.ids]
}
