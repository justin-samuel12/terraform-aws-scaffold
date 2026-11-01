# Wiring checks against a mocked AWS -- docs/network.md.
mock_provider "aws" {}

override_data {
  target = data.aws_route53_resolver_rules.hub
  values = { resolver_rule_ids = ["rslvr-rr-ad"] }
}

override_data {
  target = module.vpc.data.aws_availability_zones.available
  values = { zone_ids = ["use2-az1", "use2-az2", "use2-az3"] }
}

override_data {
  target = data.aws_ec2_transit_gateway.transit_gateway
  values = { id = "tgw-ohio" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["restricted"]
  values = { id = "tgw-rtb-restricted" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["standard"]
  values = { id = "tgw-rtb-standard" }
}

override_data {
  target = data.aws_ec2_transit_gateway_route_table.route_tables["shared"]
  values = { id = "tgw-rtb-shared" }
}

variables {
  config_path = "../../tests/config"
}

run "development" {
  command = plan

  variables {
    environment = "development"
    region      = "us-east-2"
  }

  assert {
    condition     = output.network.cidr == "10.42.0.0/16" && output.network.zones == ["use2-az1", "use2-az2", "use2-az3"]
    error_message = "Operations takes its range and three Ohio zone IDs from the IP plan."
  }

  assert {
    condition     = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id == "tgw-rtb-shared"
    error_message = "Operations is associated with the hub's shared route table."
  }

  assert {
    condition     = toset([for table in local.network.propagates_to : data.aws_ec2_transit_gateway_route_table.route_tables[table].id]) == toset(["tgw-rtb-restricted", "tgw-rtb-standard", "tgw-rtb-shared"])
    error_message = "Operations is reachable from every segment."
  }

  assert {
    condition     = length(aws_route53_resolver_rule_association.hub) == 1
    error_message = "The VPC is associated with each of the hub's forwarding rules."
  }

  assert {
    condition     = tolist(local.subnets.ops.reserved_cidrs) == tolist(["10.42.228.64/26", "10.42.230.64/26", "10.42.232.64/26"])
    error_message = "Each ops subnet reserves .64-.127 for chosen addresses."
  }

  assert {
    condition     = local.network.routes.data == "internal" && local.subnets.data.default_route == "none" && tolist(local.subnets.data.transit_routes) == tolist(["10.0.0.0/8"])
    error_message = "The data tier reaches other VPCs and HQ through the hub, and never the internet."
  }

  assert {
    condition     = output.subnets["data-az2"].cidr == "10.42.196.0/22" && output.subnets["data-az2"].zone == "use2-az2" && length(output.subnets) == 12
    error_message = "The output names each subnet as compute does: tier and zone, with its CIDR and zone ID."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["private", "data", "ops", "transit"])
    error_message = "Operations has no public tier, so no internet gateway."
  }
}

run "production" {
  command = plan

  variables {
    environment = "production"
    region      = "us-east-2"
  }

  assert {
    condition     = data.aws_ec2_transit_gateway_route_table.route_tables[local.network.segment].id == "tgw-rtb-restricted"
    error_message = "Production is associated with the hub's restricted route table."
  }

  assert {
    condition     = !contains(local.network.propagates_to, "standard")
    error_message = "Production is never propagated into standard, so staging cannot reach it."
  }

  assert {
    condition     = toset(keys(module.vpc.subnet_ids)) == toset(["private", "data", "public", "ops", "transit"])
    error_message = "Production has a public tier for internet-facing load balancers."
  }
}

run "not_in_the_ip_plan" {
  command = plan

  variables {
    environment = "staging"
    region      = "us-east-2"
  }

  expect_failures = [var.region]
}
