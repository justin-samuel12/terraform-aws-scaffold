# Load balancer files turned into load balancers, against a mocked AWS -- docs/load-balancers.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_subnets.tiers["private"]
  values = { ids = ["subnet-private-1", "subnet-private-2", "subnet-private-3"] }
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
    condition     = local.load_balancers.grafana.internal && local.load_balancers.grafana.tier == "private"
    error_message = "An internal load balancer sits in the private tier unless its file says otherwise."
  }

  assert {
    condition     = toset(keys(output.load_balancers)) == toset(["grafana"]) && toset(keys(output.load_balancers.grafana.target_group_arns)) == toset(["web"])
    error_message = "One load balancer per file, with its target groups."
  }

  assert {
    condition     = local.load_balancers.grafana.rules["old-name"].redirect.host == "grafana.example.com" && local.load_balancers.grafana.rules["old-name"].listener == "443"
    error_message = "A rule in the file redirects by host."
  }
}

run "refuses_internet_facing_without_a_public_tier" {
  command = plan

  # Operations has no public tier, so nothing in it can face the internet.
  variables {
    config_dir = "tests/public-in-operations"
  }

  expect_failures = [output.load_balancers]
}
