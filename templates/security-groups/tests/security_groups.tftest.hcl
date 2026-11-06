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
    condition     = toset(keys(local.groups)) == toset(["grafana", "grafana-lb"]) && length(local.problems) == 0
    error_message = "One group per file, named after the file."
  }

  assert {
    condition     = local.groups.grafana.ingress[0].referenced_security_group_id == "grafana-lb" && local.groups.grafana.ingress[1].referenced_security_group_id == "grafana" && local.groups.grafana.ingress[3].cidr_ipv4 == "10.42.228.0/23"
    error_message = "A rule keeps its own arguments; a group in the stack is named, its own name for traffic between its members."
  }

  assert {
    condition     = local.groups["grafana-lb"].ingress[1].prefix_list_id == "pl-0staffteam" && local.groups["grafana-lb"].tags.Team == "observability"
    error_message = "An id passes through as it is; tags are the group's own."
  }

  assert {
    condition     = length(local.groups.grafana.egress) == 0 && length(local.groups["grafana-lb"].egress) == 1
    error_message = "Egress is only what a file writes."
  }
}

run "a_prefix_list_by_name" {
  command = plan

  variables {
    config_dir  = "tests/unknown-list"
    config_path = "../../templates/security-groups/tests/referencing-on"
  }

  override_data {
    target = data.aws_ec2_managed_prefix_list.lists["staff-team"]
    values = { id = "pl-0staffteam" }
  }

  assert {
    condition     = local.groups.rdp.ingress[0].prefix_list_id == "pl-0staffteam"
    error_message = "prefix_list_id names a list from config/global.yml, found by its name."
  }
}

run "refuses_a_list_config_does_not_have" {
  command = plan

  variables {
    config_dir = "tests/unknown-list"
  }

  assert {
    condition     = contains(local.problems, "rdp.yml: prefix_list_id staff-team is not a prefix list in config/global.yml")
    error_message = "A list config does not define is named."
  }

  expect_failures = [output.ids]
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "web.yml: keys are description, tags, ingress, egress, as aws_security_group takes them"),
      contains(local.problems, "web.yml: a rule in ingress takes the arguments of aws_vpc_security_group_ingress_rule: description, ip_protocol, from_port, to_port, cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id"),
    ])
    error_message = "load_balancer and source are not arguments, so they are refused."
  }

  expect_failures = [output.ids]
}

run "refuses_a_rule_without_protocol_or_with_two_peers" {
  command = plan

  variables {
    config_dir = "tests/no-protocol"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "web.yml: the ingress rule \"HTTPS\" needs ip_protocol (tcp, udp, icmp, icmpv6 or -1)"),
      contains(local.problems, "web.yml: the ingress rule \"HTTPS\" names exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id"),
      contains(local.problems, "web.yml: referenced_security_group_id missing is not a group in this stack (a file named missing.yml)"),
    ])
    error_message = "Each mistake in a rule is named."
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
    condition     = local.groups["monitoring-agent"].ingress[0].referenced_security_group_id == "sg-operations-monitoring"
    error_message = "referenced_security_group_id <environment>/<group> is that environment's group, found by its tags."
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

run "read_from_folders" {
  command = plan

  variables {
    config_dir = "tests/two-folders"
  }

  assert {
    condition     = toset(keys(local.groups)) == toset(["grafana", "grafana-lb"])
    error_message = "Files in any folder are read, each named after its file."
  }

  assert {
    condition     = contains(local.problems, "grafana.yml is in more than one folder (elsewhere/grafana.yml, servers/grafana.yml); a group's name is its file's, so it must be unique")
    error_message = "The same name in two folders is refused, never one quietly chosen."
  }

  expect_failures = [output.ids]
}

run "empty_lists_are_no_rules" {
  command = plan

  variables {
    config_dir = "tests/empty-lists"
  }

  assert {
    condition     = length(local.problems) == 0 && length(local.groups.closed.ingress) == 0 && length(local.groups.closed.egress) == 0
    error_message = "ingress: or egress: left empty is a group with no rules that way."
  }
}

run "refuses_a_group_of_no_known_kind" {
  command = plan

  variables {
    config_dir = "tests/no-kind"
  }

  assert {
    condition     = contains(local.problems, "web.yml: tags.Kind is required, one of load-balancer, server, database, client, endpoint") && contains(local.problems, "web.yml: the tags Name and Key are the stack's own; give yours another name")
    error_message = "Every group says what kind of thing it guards, from a fixed list, and leaves Name and Key to the stack."
  }

  expect_failures = [output.ids]
}
