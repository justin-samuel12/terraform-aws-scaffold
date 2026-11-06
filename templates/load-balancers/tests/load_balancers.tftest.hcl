mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_subnet.subnets["private-az1"]
  values = { id = "subnet-private-1" }
}

override_data {
  target = data.aws_subnet.subnets["private-az2"]
  values = { id = "subnet-private-2" }
}

override_data {
  target = data.aws_subnet.subnets["private-az3"]
  values = { id = "subnet-private-3" }
}

override_data {
  target = data.aws_security_group.groups["grafana-lb"]
  values = { id = "sg-grafana-lb" }
}

override_data {
  target = data.aws_acm_certificate.certificates["grafana.example.com"]
  values = { arn = "arn:aws:acm:us-east-2:111111111111:certificate/example" }
}

override_data {
  target = data.aws_s3_bucket.access_logs[0]
  values = { id = "lb-logs-111111111111-us-east-2" }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "internal_grafana" {
  command = plan

  variables {
    config_dir = "tests/internal"
  }

  assert {
    condition     = length(local.problems) == 0 && toset(keys(output.load_balancers)) == toset(["grafana"]) && toset(keys(output.load_balancers.grafana.target_group_arns)) == toset(["web"])
    error_message = "One load balancer per file, with its target groups."
  }

  assert {
    condition     = jsonencode(local.resolved.grafana.subnets) == jsonencode(["subnet-private-1", "subnet-private-2", "subnet-0123456789abcdef0"]) && jsonencode(local.resolved.grafana.security_groups) == jsonencode(["sg-grafana-lb"])
    error_message = "Subnets and security groups are found by name; an ID passes through."
  }

  assert {
    condition     = local.resolved.grafana.listeners[0].certificate_arn == "arn:aws:acm:us-east-2:111111111111:certificate/example" && local.resolved.grafana.listeners[0].default_action.target_group_arn == "web"
    error_message = "A listener's certificate_arn is found by its domain, and its default_action names a target group."
  }

  assert {
    condition     = local.load_balancers.grafana.listener_rules["old-name"].action.redirect.host == "grafana.example.com" && local.load_balancers.grafana.listener_rules["old-name"].listener_arn == "443" && jsonencode(local.load_balancers.grafana.listener_rules["old-name"].condition.host_header.values) == jsonencode(["metrics.example.com"])
    error_message = "A listener rule names its listener by port and keeps its own action and condition."
  }

  assert {
    condition     = local.load_balancers.grafana.target_groups.web.deregistration_delay == 60 && local.load_balancers.grafana.target_groups.web.health_check.matcher == "200-399"
    error_message = "A target group is what its file writes."
  }
}

run "listener_certificates" {
  command = plan

  variables {
    config_dir = "tests/several-certificates"
  }

  override_data {
    target = data.aws_acm_certificate.certificates["*.example.org"]
    values = { arn = "arn:aws:acm:us-east-2:111111111111:certificate/org" }
  }

  assert {
    condition = jsonencode(local.resolved.staff.listener_certificates) == jsonencode({
      "443 *.example.org"                                      = { listener_arn = "443", certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/org" }
      "443 arn:aws:acm:us-east-2:111111111111:certificate/net" = { listener_arn = "443", certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/net" }
    }) && toset(keys(output.load_balancers)) == toset(["staff"])
    error_message = "A listener certificate is found by its domain, and an ARN passes through."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "web.yml: keys are load_balancer_type, internal, subnets, security_groups, listeners, target_groups, listener_rules, listener_certificates: aws_lb's load_balancer_type, internal, subnets and security_groups, then its aws_lb_listener, aws_lb_target_group, aws_lb_listener_rule and aws_lb_listener_certificate resources"),
      contains(local.problems, "web.yml: a listener takes the arguments of aws_lb_listener: port, protocol, certificate_arn, default_action (ssl_policy is fixed)"),
      contains(local.problems, "web.yml: the listener on port 80 needs default_action"),
      contains(local.problems, "web.yml: default_action of the listener on port 443 takes type, target_group_arn, redirect, fixed_response"),
      contains(local.problems, "web.yml: the listener rule old-name takes the arguments of aws_lb_listener_rule: listener_arn, priority, action, condition"),
      contains(local.problems, "web.yml: subnets lists at least two subnets"),
    ])
    error_message = "tier, certificate, targets, redirect: true and a rule's listener are not arguments, so they are refused."
  }

  expect_failures = [output.load_balancers]
}

run "refuses_a_subnet_the_vpc_does_not_have" {
  command = plan

  variables {
    config_dir = "tests/public-in-operations"
  }

  assert {
    condition     = contains(local.problems, "web.yml: subnets: public-az1 is not a subnet of the operations VPC in us-east-2 (data-az1, data-az2, data-az3, ops-az1, ops-az2, ops-az3, private-az1, private-az2, private-az3, transit-az1, transit-az2, transit-az3), nor a subnet ID")
    error_message = "Nothing internet-facing in operations, which has no public subnets."
  }

  expect_failures = [output.load_balancers]
}

run "read_from_folders" {
  command = plan

  variables {
    config_dir = "tests/two-folders"
  }

  assert {
    condition     = contains(local.problems, "grafana.yml is in more than one folder (application/grafana.yml, network/grafana.yml); a load balancer's name is its file's, so it must be unique")
    error_message = "Files are read from the stack's folders, and one name in two of them is refused rather than one silently winning."
  }

  expect_failures = [output.load_balancers]
}
