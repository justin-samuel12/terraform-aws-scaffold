# What the module builds and refuses, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {}

variables {
  records = {
    api     = { zone_id = "Z0PUBLIC", name = "api.example.com", alias = { name = "external-123.us-east-2.elb.amazonaws.com", zone_id = "Z3AADJGX6KTTL2" } }
    grafana = { zone_id = "Z0PRIVATE", name = "grafana.internal.example.com", values = ["10.42.228.70"] }
  }
}

run "alias_and_address" {
  command = plan

  assert {
    condition     = length(aws_route53_record.records["api"].alias) == 1 && aws_route53_record.records["grafana"].ttl == 300
    error_message = "A load balancer by alias; a server by address."
  }
}

run "rejects_alias_and_values" {
  command = plan

  variables {
    records = { both = { zone_id = "Z0", name = "x.example.com", values = ["10.0.0.1"], alias = { name = "lb", zone_id = "Z1" } } }
  }

  expect_failures = [var.records]
}
