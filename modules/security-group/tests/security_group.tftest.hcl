# What the module builds and what it refuses, against a mocked AWS -- docs/security-groups.md.
mock_provider "aws" {}

variables {
  vpc_id = "vpc-0123456789abcdef0"
  groups = {
    app = {
      description = "Application servers"
      ingress = [
        { description = "From the load balancer", protocol = "tcp", from_port = 443, to_port = 443, group = "web-lb" },
        { description = "Cluster traffic", protocol = "tcp", from_port = 7000, to_port = 7001, group = "self" },
        { description = "From ops", protocol = "tcp", from_port = 22, to_port = 22, cidr = "10.42.228.0/23" },
        { description = "From the staff networks", protocol = "tcp", from_port = 3389, to_port = 3389, prefix_list = "pl-0staffteam" },
      ]
    }
    web-lb = {
      description   = "Public load balancer"
      load_balancer = true
      ingress = [
        { description = "HTTPS from anywhere", protocol = "tcp", from_port = 443, to_port = 443, cidr = "0.0.0.0/0" },
      ]
      egress = [
        { description = "To the application", protocol = "tcp", from_port = 443, to_port = 443, group = "app" },
      ]
    }
  }
}

run "groups_and_rules" {
  command = plan

  assert {
    condition     = toset(keys(aws_security_group.groups)) == toset(["app", "web-lb"])
    error_message = "One security group per entry, named after it."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.rules) == 5 && aws_vpc_security_group_ingress_rule.rules["app/ingress/tcp/3389-3389/pl-0staffteam"].prefix_list_id == "pl-0staffteam"
    error_message = "One ingress resource per rule."
  }

  assert {
    condition     = length([for key, r in aws_vpc_security_group_egress_rule.rules : r if startswith(key, "app/")]) == 2
    error_message = "A group without egress gets the default: internal traffic and HTTPS out."
  }

  assert {
    condition     = length([for key, r in aws_vpc_security_group_egress_rule.rules : r if startswith(key, "web-lb/")]) == 1
    error_message = "A group's own egress replaces the default."
  }

  assert {
    condition     = contains(keys(aws_vpc_security_group_ingress_rule.rules), "app/ingress/tcp/7000-7001/self")
    error_message = "A rule is keyed by what it allows, so reordering a file changes nothing."
  }
}

run "rejects_internet_on_a_server" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = "SSH from anywhere", protocol = "tcp", from_port = 22, to_port = 22, cidr = "0.0.0.0/0" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_unknown_group" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = "From nowhere", protocol = "tcp", from_port = 443, to_port = 443, group = "missing" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_missing_description" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = " ", protocol = "tcp", from_port = 443, to_port = 443, cidr = "10.0.0.0/8" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_reversed_ports" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = "Backwards", protocol = "tcp", from_port = 9000, to_port = 8000, cidr = "10.0.0.0/8" }]
      }
    }
  }

  expect_failures = [var.groups]
}
