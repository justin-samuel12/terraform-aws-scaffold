# Record files turned into Route 53 records, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {
  alias = "hub"
}

mock_provider "aws" {}

override_data {
  target = data.aws_route53_zone.zones["example.com|false"]
  values = { zone_id = "Z0PUBLIC" }
}

override_data {
  target = data.aws_route53_zone.zones["internal.example.com|true"]
  values = { zone_id = "Z0PRIVATE" }
}

override_data {
  target = data.aws_lb.load_balancers["external"]
  values = { dns_name = "external-123.us-east-2.elb.amazonaws.com", zone_id = "Z3AADJGX6KTTL2" }
}

override_data {
  target = data.aws_instance.servers["grafana-01"]
  values = { private_ip = "10.42.228.70" }
}

variables {
  environment = "operations"
}

run "alias_and_server" {
  command = plan

  variables {
    config_dir = "tests/records"
  }

  assert {
    condition     = toset(keys(output.names)) == toset(["api", "grafana"])
    error_message = "One record per file: a load balancer by alias, a server by its address."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.names == {}
    error_message = "Without files, no records."
  }
}
