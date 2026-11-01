# What the module builds and refuses, against a mocked AWS -- docs/load-balancers.md.
mock_provider "aws" {}

variables {
  name               = "grafana"
  type               = "application"
  internal           = true
  vpc_id             = "vpc-development"
  subnet_ids         = ["subnet-private-1", "subnet-private-2", "subnet-private-3"]
  security_group_ids = ["sg-grafana-lb"]
  certificate_arn    = "arn:aws:acm:us-east-2:111111111111:certificate/example"
  access_logs_bucket = "lb-logs-111111111111-us-east-2"
  targets = {
    web = { port = 3000, protocol = "HTTP", health_check_path = "/api/health" }
  }
  listeners = {
    "443" = { protocol = "HTTPS", target = "web" }
    "80"  = { protocol = "HTTP", redirect = true }
  }
}

run "internal_grafana" {
  command = plan

  assert {
    condition     = aws_lb.load_balancer.internal && aws_lb.load_balancer.enable_deletion_protection && aws_lb.load_balancer.drop_invalid_header_fields && aws_lb.load_balancer.access_logs[0].enabled
    error_message = "Internal, protected from deletion, dropping malformed headers, and logging every request."
  }

  assert {
    condition     = aws_lb_listener.listeners["443"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS accepts only TLS 1.2 and 1.3."
  }

  assert {
    condition     = aws_lb_listener.listeners["80"].default_action[0].type == "redirect"
    error_message = "Port 80 only redirects to HTTPS."
  }

  assert {
    condition     = startswith(aws_lb_target_group.targets["web"].name, "grafana-web-") && aws_lb_target_group.targets["web"].tags.Name == "grafana-web" && aws_lb_target_group.targets["web"].health_check[0].path == "/api/health"
    error_message = "Target groups are named <load balancer>-<target>, with their health check."
  }
}

run "rejects_https_without_certificate" {
  command = plan

  variables {
    certificate_arn = null
  }

  expect_failures = [var.listeners]
}

run "rejects_plain_http_on_the_internet" {
  command = plan

  variables {
    internal  = false
    listeners = { "80" = { protocol = "HTTP", target = "web" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_unknown_target" {
  command = plan

  variables {
    listeners = { "443" = { protocol = "HTTPS", target = "missing" } }
  }

  expect_failures = [var.listeners]
}

run "rules" {
  command = plan

  variables {
    rules = {
      portal = { listener = "443", priority = 10, hosts = ["portal.example.com"], redirect = { host = "www.example.com", path = "/p/login" } }
      api    = { listener = "443", priority = 20, paths = ["/api/*"], target = "web" }
    }
  }

  assert {
    condition     = one(aws_lb_listener_rule.rules["portal"].action).type == "redirect" && one(aws_lb_listener_rule.rules["api"].action).type == "forward"
    error_message = "Rules redirect or forward by host and path."
  }
}

run "rejects_two_actions" {
  command = plan

  variables {
    rules = { both = { listener = "443", priority = 10, hosts = ["a.example.com"], target = "web", fixed_response = { status_code = "404" } } }
  }

  expect_failures = [var.rules]
}

run "rejects_shared_priority" {
  command = plan

  variables {
    rules = {
      one = { listener = "443", priority = 10, hosts = ["a.example.com"], target = "web" }
      two = { listener = "443", priority = 10, hosts = ["b.example.com"], target = "web" }
    }
  }

  expect_failures = [var.rules]
}

run "answers_404_unless_claimed" {
  command = plan

  variables {
    listeners = { "443" = { protocol = "HTTPS" } }
  }

  assert {
    condition     = aws_lb_listener.listeners["443"].default_action[0].type == "fixed-response" && aws_lb_listener.listeners["443"].default_action[0].fixed_response[0].status_code == "404"
    error_message = "A listener with no target answers 404 to anything no rule or application claims."
  }
}

run "rejects_application_priorities" {
  command = plan

  variables {
    rules = { late = { listener = "443", priority = 1000, hosts = ["a.example.com"], target = "web" } }
  }

  expect_failures = [var.rules]
}
