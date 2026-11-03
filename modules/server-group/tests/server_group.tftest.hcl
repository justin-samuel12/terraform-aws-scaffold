# What the module builds, with and without CodeDeploy, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {
  alias = "hub"
}

mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { root_device_name = "/dev/xvda" }
  }
}

variables {
  name        = "grafana"
  environment = "operations"
  vpc_id      = "vpc-operations"
  servers = {
    members = {
      grafana-01 = { subnet_id = "subnet-ops-1", subnet = "ops-az1", instance_type = "t3.medium" }
      grafana-02 = { subnet_id = "subnet-ops-2", subnet = "ops-az2", instance_type = "t3.medium" }
    }
    image_id           = "ami-0123456789abcdef0"
    security_group_ids = ["sg-grafana"]
    instance_profile   = "grafana"
    kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  }
  port   = 3000
  health = "/api/health"
  routes = [{ listener_arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/internal/abc/def", hosts = ["grafana.example.com"], priority = 1010 }]
  names  = [{ zone_id = "Z0PRIVATE", name = "grafana.example.com", lb_dns_name = "internal-123.us-east-2.elb.amazonaws.com", lb_zone_id = "Z3AADJGX6KTTL2" }]
}

run "routed" {
  command = plan

  assert {
    condition     = aws_lb_target_group.group[0].port == 3000 && startswith(aws_lb_target_group.group[0].name, "operations-grafana-") && length(aws_lb_target_group.group[0].name) == 27 && !aws_lb_target_group.group[0].stickiness[0].enabled && aws_lb_target_group.group[0].health_check[0].path == "/api/health" && length(aws_lb_listener_rule.routes) == 1
    error_message = "A target group on its port and health check, and its rule on the shared listener."
  }

  assert {
    condition     = output.size == length(var.servers.members)
    error_message = "Its size, for deciding whether deployments drain servers from the load balancer, is its number of servers."
  }
}

run "internal" {
  command = plan

  variables {
    routes = []
    names  = []
  }

  assert {
    condition     = length(aws_lb_target_group.group) == 0 && length(aws_lb_listener_rule.routes) == 0
    error_message = "Without routes: just the servers, in no target group of their own."
  }
}

run "joins_a_network_load_balancer_too" {
  command = plan

  variables {
    target  = { protocol = "HTTPS", stickiness = 3600 }
    targets = { "internal-nlb/syslog" = { arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:targetgroup/internal-nlb-syslog-ab12/1", name = "internal-nlb-syslog-ab12", port = 514 } }
  }

  assert {
    condition     = aws_lb_target_group.group[0].protocol == "HTTPS" && aws_lb_target_group.group[0].stickiness[0].cookie_duration == 3600
    error_message = "Its own group speaks HTTPS to it, with sticky sessions."
  }

  assert {
    condition     = length(output.target_group_names) == 2 && contains(output.target_group_names, "internal-nlb-syslog-ab12")
    error_message = "Every group its servers are in, its own and the network load balancer's, so a deployment takes each server out of all of them."
  }
}

run "rejects_low_priority" {
  command = plan

  variables {
    routes = [{ listener_arn = "arn:aws:elasticloadbalancing:us-east-2:111111111111:listener/app/internal/abc/def", hosts = ["grafana.example.com"], priority = 10 }]
  }

  expect_failures = [var.routes]
}

run "as_an_auto_scaling_group" {
  command = plan

  variables {
    instance_type = "m6i.large"
    servers = {
      members            = {}
      image_id           = "ami-0123456789abcdef0"
      security_group_ids = ["sg-grafana"]
      instance_profile   = "grafana"
      kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
    }
    autoscaling = {
      subnet_ids       = ["subnet-ops-1", "subnet-ops-2", "subnet-ops-3"]
      min_size         = 2
      max_size         = 4
      desired_capacity = 2
    }
  }

  assert {
    condition     = length(module.autoscaling) == 1 && length(module.servers.servers) == 0
    error_message = "An Auto Scaling group instead of fixed servers."
  }

  assert {
    condition     = output.size == 4
    error_message = "An Auto Scaling group counts as its largest size, for whether deployments drain servers first."
  }
}
