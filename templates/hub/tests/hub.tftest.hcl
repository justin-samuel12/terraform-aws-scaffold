# Wiring checks against a mocked AWS -- docs/network.md.
mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "ohio_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
  }

  variables {
    region = "us-east-2"
  }

  assert {
    condition     = output.network.amazon_side_asn == 64512 && output.network.cidr == "10.40.0.0/20"
    error_message = "The Ohio hub uses its own ASN and egress range from the IP plan."
  }

  assert {
    condition     = toset(keys(module.transit_gateway.route_table_ids)) == toset(["restricted", "standard", "shared"])
    error_message = "The hub has one route table per segment."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["public", "transit", "dns"])
    error_message = "The egress VPC has its public and transit tiers, and a dns tier for the resolver endpoints."
  }

  assert {
    condition     = length(module.route53_resolver) == 1 && output.dns.rule_ids == {} && output.prefix_list_ids == {}
    error_message = "The resolver is ready but builds nothing, and there are no prefix lists, until config/global.yml lists them."
  }

  assert {
    condition     = length(module.vpn) == 0
    error_message = "No VPN until HQ's public IP is set in the IP plan."
  }
}

run "oregon_hub" {
  command = plan

  override_data {
    target = module.vpc.data.aws_availability_zones.available
    values = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3", "usw2-az4"] }
  }

  variables {
    region = "us-west-2"
  }

  assert {
    condition     = output.network.amazon_side_asn == 64513 && output.network.cidr == "10.60.0.0/20"
    error_message = "The Oregon hub has its own ASN and egress range."
  }
}
