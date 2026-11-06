mock_provider "aws" {}

variables {
  name               = "grafana"
  load_balancer_type = "application"
  internal           = true
  vpc_id             = "vpc-operations"
  subnets            = ["subnet-private-1", "subnet-private-2", "subnet-private-3"]
  security_groups    = ["sg-grafana-lb"]
  access_logs_bucket = "lb-logs-111111111111-us-east-2"
  target_groups = {
    web = {
      port                 = 3000
      protocol             = "HTTP"
      target_type          = "instance"
      deregistration_delay = 60
      health_check         = { path = "/api/health", matcher = "200-399" }
    }
  }
  listeners = [
    {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/example"
      default_action  = { type = "forward", target_group_arn = "web" }
    },
    {
      port           = 80
      protocol       = "HTTP"
      default_action = { type = "redirect", redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" } }
    },
  ]
}

run "internal_grafana" {
  command = plan

  assert {
    condition     = aws_lb.load_balancer.internal && aws_lb.load_balancer.enable_deletion_protection && aws_lb.load_balancer.drop_invalid_header_fields && aws_lb.load_balancer.access_logs[0].enabled
    error_message = "Internal, protected from deletion, dropping malformed headers, and logging every request."
  }

  assert {
    condition     = aws_lb_listener.listeners["443"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.listeners["443"].certificate_arn == "arn:aws:acm:us-east-2:111111111111:certificate/example"
    error_message = "HTTPS accepts only TLS 1.2 and 1.3, with the listener's own certificate."
  }

  assert {
    condition     = aws_lb_listener.listeners["80"].default_action[0].type == "redirect" && aws_lb_listener.listeners["80"].default_action[0].redirect[0].protocol == "HTTPS"
    error_message = "Port 80's default_action is the redirect it was given."
  }

  assert {
    condition     = startswith(aws_lb_target_group.targets["web"].name, "grafana-web-") && aws_lb_target_group.targets["web"].tags.Name == "grafana-web" && aws_lb_target_group.targets["web"].health_check[0].path == "/api/health" && aws_lb_target_group.targets["web"].deregistration_delay == "60" && aws_lb_target_group.targets["web"].target_type == "instance"
    error_message = "Target groups are named <load balancer>-<target group>, with the arguments they were given."
  }
}

run "a_fixed_response_is_written" {
  command = plan

  variables {
    listeners = [
      {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/example"
        default_action  = { type = "fixed-response", fixed_response = { content_type = "text/plain", message_body = "Not found", status_code = "404" } }
      },
    ]
  }

  assert {
    condition     = aws_lb_listener.listeners["443"].default_action[0].type == "fixed-response" && aws_lb_listener.listeners["443"].default_action[0].fixed_response[0].status_code == "404"
    error_message = "A listener answers what its default_action says."
  }
}

run "rejects_https_without_certificate" {
  command = plan

  variables {
    listeners = [{ port = 443, protocol = "HTTPS", default_action = { type = "forward", target_group_arn = "web" } }]
  }

  expect_failures = [var.listeners]
}

run "rejects_plain_http_on_the_internet" {
  command = plan

  variables {
    internal  = false
    listeners = [{ port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_arn = "web" } }]
  }

  expect_failures = [var.listeners]
}

run "rejects_unknown_target_group" {
  command = plan

  variables {
    listeners = [{ port = 80, protocol = "HTTP", default_action = { type = "forward", target_group_arn = "missing" } }]
  }

  expect_failures = [var.listeners]
}

run "rejects_an_action_of_the_wrong_type" {
  command = plan

  variables {
    listeners = [{ port = 80, protocol = "HTTP", default_action = { type = "redirect", target_group_arn = "web" } }]
  }

  expect_failures = [var.listeners]
}

run "listener_rules" {
  command = plan

  variables {
    listener_rules = {
      portal = {
        listener_arn = "443"
        priority     = 10
        action       = { type = "redirect", redirect = { host = "www.example.com", path = "/p/login", status_code = "HTTP_301" } }
        condition    = { host_header = { values = ["portal.example.com"] } }
      }
      api = {
        listener_arn = "443"
        priority     = 20
        action       = { type = "forward", target_group_arn = "web" }
        condition    = { path_pattern = { values = ["/api/*"] } }
      }
    }
  }

  assert {
    condition     = one(aws_lb_listener_rule.rules["portal"].action).type == "redirect" && one(aws_lb_listener_rule.rules["api"].action).type == "forward"
    error_message = "Rules redirect or forward by host and path."
  }

  assert {
    condition     = jsonencode(one(aws_lb_listener_rule.rules["portal"].condition).host_header[0].values) == jsonencode(["portal.example.com"])
    error_message = "A rule matches the hosts it was given."
  }
}

run "rejects_two_actions" {
  command = plan

  variables {
    listener_rules = {
      both = {
        listener_arn = "443"
        priority     = 10
        action       = { type = "forward", target_group_arn = "web", fixed_response = { content_type = "text/plain", status_code = "404" } }
        condition    = { host_header = { values = ["a.example.com"] } }
      }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_shared_priority" {
  command = plan

  variables {
    listener_rules = {
      one = { listener_arn = "443", priority = 10, action = { type = "forward", target_group_arn = "web" }, condition = { host_header = { values = ["a.example.com"] } } }
      two = { listener_arn = "443", priority = 10, action = { type = "forward", target_group_arn = "web" }, condition = { host_header = { values = ["b.example.com"] } } }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_application_priorities" {
  command = plan

  variables {
    listener_rules = {
      late = { listener_arn = "443", priority = 1000, action = { type = "forward", target_group_arn = "web" }, condition = { host_header = { values = ["a.example.com"] } } }
    }
  }

  expect_failures = [var.listener_rules]
}

run "listener_certificates" {
  command = plan

  variables {
    listener_certificates = {
      "443 *.example.org" = { listener_arn = "443", certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/org" }
    }
  }

  assert {
    condition     = jsonencode(keys(aws_lb_listener_certificate.additional)) == jsonencode(["443 *.example.org"]) && aws_lb_listener_certificate.additional["443 *.example.org"].certificate_arn == "arn:aws:acm:us-east-2:111111111111:certificate/org"
    error_message = "A listener certificate is added to the listener it names."
  }
}

run "rejects_a_certificate_on_plain_http" {
  command = plan

  variables {
    listener_certificates = {
      "80 *.example.org" = { listener_arn = "80", certificate_arn = "arn:aws:acm:us-east-2:111111111111:certificate/org" }
    }
  }

  expect_failures = [var.listener_certificates]
}
