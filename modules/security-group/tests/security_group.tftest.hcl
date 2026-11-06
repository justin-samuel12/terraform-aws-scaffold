mock_provider "aws" {}

variables {
  vpc_id = "vpc-0123456789abcdef0"
  groups = {
    app = {
      description = "Application servers"
      tags        = { Team = "web" }
      ingress = [
        { description = "From the load balancer", ip_protocol = "tcp", from_port = 443, to_port = 443, referenced_security_group_id = "web-lb" },
        { description = "Cluster traffic", ip_protocol = "tcp", from_port = 7000, to_port = 7001, referenced_security_group_id = "app" },
        { description = "From ops", ip_protocol = "tcp", from_port = 22, to_port = 22, cidr_ipv4 = "10.42.228.0/23" },
        { description = "From the staff networks", ip_protocol = "tcp", from_port = 3389, to_port = 3389, prefix_list_id = "pl-0staffteam" },
        { description = "From the collectors of another environment", ip_protocol = "tcp", from_port = 10050, to_port = 10050, referenced_security_group_id = "sg-0collectors" },
      ]
      egress = [
        { description = "Everything internal", ip_protocol = "-1", cidr_ipv4 = "10.0.0.0/8" },
      ]
    }
    web-lb = {
      description = "Public load balancer"
      ingress = [
        { description = "HTTPS from anywhere", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" },
        { description = "HTTP from anywhere, redirected to HTTPS", ip_protocol = "tcp", from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" },
        { description = "HTTPS from anywhere on IPv6", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv6 = "::/0" },
      ]
      egress = [
        { description = "To the application", ip_protocol = "tcp", from_port = 443, to_port = 443, referenced_security_group_id = "app" },
      ]
    }
    closed = {
      description = "Takes nothing in and sends nothing out"
    }
  }
}

run "groups_and_rules" {
  command = plan

  assert {
    condition     = toset(keys(aws_security_group.groups)) == toset(["app", "web-lb", "closed"])
    error_message = "One security group per entry, named after it."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.rules) == 8 && aws_vpc_security_group_ingress_rule.rules["app/ingress/tcp/3389-3389/pl-0staffteam"].prefix_list_id == "pl-0staffteam"
    error_message = "One ingress resource per rule, with the rule's own arguments."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rules["app/ingress/tcp/10050-10050/sg-0collectors"].referenced_security_group_id == "sg-0collectors" && aws_vpc_security_group_ingress_rule.rules["web-lb/ingress/tcp/443-443/::/0"].cidr_ipv6 == "::/0"
    error_message = "A group's id passes through as it is; cidr_ipv6 is kept."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.rules) == 2 && length([for key, r in aws_vpc_security_group_egress_rule.rules : r if startswith(key, "closed/")]) == 0
    error_message = "Egress is only what a group writes: none written, none made."
  }

  assert {
    condition     = aws_security_group.groups["app"].name_prefix == "app-" && jsonencode(aws_security_group.groups["app"].tags) == jsonencode({ Key = "app", Name = "app", Team = "web" })
    error_message = "Groups are named with a prefix so a new description builds a new group first; their tags are kept, with Key and, without an Environment default tag, Name set to the group's."
  }

  assert {
    condition     = contains(keys(aws_vpc_security_group_ingress_rule.rules), "app/ingress/tcp/7000-7001/app")
    error_message = "A rule is keyed by what it allows, so reordering a file changes nothing."
  }
}

run "icmp_types_and_codes" {
  command = plan

  variables {
    groups = {
      cluster = {
        description = "Cluster nodes"
        ingress = [
          { description = "Any ICMP from the other nodes", ip_protocol = "icmp", from_port = -1, to_port = -1, referenced_security_group_id = "cluster" },
          { description = "Ping from the other nodes", ip_protocol = "icmp", from_port = 8, to_port = 0, referenced_security_group_id = "cluster" },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.rules) == 2
    error_message = "For icmp, from_port is the type and to_port the code, -1 for all, so type 8 code 0 is not a reversed range."
  }
}

run "rejects_internet_on_other_ports" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = "SSH from anywhere", ip_protocol = "tcp", from_port = 22, to_port = 22, cidr_ipv4 = "0.0.0.0/0" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_a_range_from_the_internet" {
  command = plan

  variables {
    groups = {
      web-lb = {
        description = "A public load balancer"
        ingress     = [{ description = "Everything from anywhere", ip_protocol = "tcp", from_port = 80, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }]
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
        ingress     = [{ description = "From nowhere", ip_protocol = "tcp", from_port = 443, to_port = 443, referenced_security_group_id = "missing" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_two_peers_in_one_rule" {
  command = plan

  variables {
    groups = {
      app = {
        description = "Application servers"
        ingress     = [{ description = "Two at once", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/8", prefix_list_id = "pl-0staffteam" }]
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
        ingress     = [{ description = " ", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/8" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "rejects_characters_aws_refuses" {
  command = plan

  variables {
    groups = {
      app = {
        description = "The application's servers"
        ingress     = [{ description = "HTTPS from the load balancer", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/8" }]
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
        ingress     = [{ description = "Backwards", ip_protocol = "tcp", from_port = 9000, to_port = 8000, cidr_ipv4 = "10.0.0.0/8" }]
      }
    }
  }

  expect_failures = [var.groups]
}

run "named_for_the_console" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "staging" } }
  }

  assert {
    condition     = aws_security_group.groups["web-lb"].tags.Name == "Staging - web-lb" && aws_security_group.groups["web-lb"].tags.Key == "web-lb" && aws_security_group.groups["web-lb"].name_prefix == "web-lb-"
    error_message = "A group's Name tag is its environment and its name; its Key tag, which stacks find it by, and its AWS name stay the group's own."
  }
}
