mock_provider "aws" {}

variables {
  records = {
    api     = { zone_id = "Z0PUBLIC", name = "api.example.com", type = "A", alias = { name = "external-123.us-east-2.elb.amazonaws.com", zone_id = "Z3AADJGX6KTTL2", evaluate_target_health = true } }
    grafana = { zone_id = "Z0PRIVATE", name = "grafana.internal.example.com", type = "A", ttl = 300, records = ["10.42.228.70"] }
  }
}

run "alias_and_address" {
  command = plan

  assert {
    condition     = length(aws_route53_record.records["api"].alias) == 1 && aws_route53_record.records["api"].ttl == null && aws_route53_record.records["grafana"].ttl == 300
    error_message = "An alias has no ttl; an address record keeps the ttl it was given."
  }

  assert {
    condition     = toset(aws_route53_record.records["grafana"].records) == toset(["10.42.228.70"])
    error_message = "records are written as given."
  }
}

run "rejects_alias_and_records" {
  command = plan

  variables {
    records = { both = { zone_id = "Z0", name = "x.example.com", type = "A", ttl = 300, records = ["10.0.0.1"], alias = { name = "lb", zone_id = "Z1", evaluate_target_health = true } } }
  }

  expect_failures = [var.records]
}
