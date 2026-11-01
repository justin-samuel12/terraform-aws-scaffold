# What the module builds and refuses, against a mocked AWS -- docs/network.md.
mock_provider "aws" {}

variables {
  name          = "dns-01"
  vpc_id        = "vpc-hub"
  subnet_ids    = ["subnet-dns-1", "subnet-dns-2", "subnet-dns-3"]
  clients_cidrs = ["10.0.0.0/8"]
  inbound       = true
  forward       = { "ad.example.com" = ["10.10.128.6", "10.10.132.6"] }
}

run "inbound_and_forwarding" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_endpoint.inbound) == 1 && length(aws_route53_resolver_endpoint.outbound) == 1
    error_message = "Inbound for HQ asking AWS, outbound for AWS asking HQ."
  }

  assert {
    condition     = aws_route53_resolver_rule.forward["ad.example.com"].rule_type == "FORWARD" && length(aws_route53_resolver_rule.forward["ad.example.com"].target_ip) == 2
    error_message = "One forwarding rule per domain, to HQ's DNS servers."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.dns) == 2
    error_message = "DNS over TCP and UDP, from our VPCs and HQ only."
  }
}

run "nothing_until_configured" {
  command = plan

  variables {
    inbound = false
    forward = {}
  }

  assert {
    condition     = length(aws_security_group.resolver) == 0 && length(aws_route53_resolver_endpoint.outbound) == 0
    error_message = "With no inbound and no domains, nothing is built and nothing is paid for."
  }
}

run "rejects_one_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-dns-1"]
  }

  expect_failures = [var.subnet_ids]
}
