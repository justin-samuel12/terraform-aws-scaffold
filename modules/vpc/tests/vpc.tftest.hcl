mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3", "usw2-az4"] }
}

variables {
  name                  = "vpc-01"
  cidr_block            = "10.62.0.0/16"
  availability_zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3"]
}

run "spoke" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "transit" }
      data    = { cidrs = ["10.62.96.0/21", "10.62.104.0/21", "10.62.112.0/21"], default_route = "none" }
      transit = { cidrs = ["10.62.252.0/28", "10.62.252.16/28", "10.62.252.32/28"], default_route = "none" }
    }
    transit_gateway = {
      id                          = "tgw-0123456789abcdef0"
      subnets                     = "transit"
      association_route_table_id  = "tgw-rtb-standard"
      propagation_route_table_ids = { standard = "tgw-rtb-standard", shared = "tgw-rtb-shared" }
    }
  }

  assert {
    condition     = length(aws_subnet.subnets) == 9 && length(aws_route_table.route_tables) == 9
    error_message = "A spoke with three tiers in three zones needs nine subnets, each with its own route table."
  }

  assert {
    condition     = length(aws_internet_gateway.internet_gateway) == 0 && length(aws_nat_gateway.nat_gateways) == 0
    error_message = "A spoke with no internet tier has no internet or NAT gateway; egress goes through the hub."
  }

  assert {
    condition     = length(aws_route.default_routes) == 3 && aws_route.default_routes["private-usw2-az1"].transit_gateway_id == "tgw-0123456789abcdef0"
    error_message = "Only the private tier sends its default route to the Transit Gateway."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_propagation.route_table_propagations) == 2
    error_message = "The attachment propagates into each listed route table."
  }

  assert {
    condition     = aws_subnet.subnets["data-usw2-az2"].tags.Name == "vpc-01-data-usw2-az2" && aws_subnet.subnets["data-usw2-az2"].tags.Subnet == "data-az2" && aws_subnet.subnets["data-usw2-az2"].tags.Tier == "data"
    error_message = "Subnet names follow <vpc>-<tier>-<zone letter>."
  }
}

run "egress" {
  command = plan

  variables {
    cidr_block = "10.60.0.0/20"
    subnets = {
      public  = { cidrs = ["10.60.0.0/24", "10.60.1.0/24", "10.60.2.0/24"], default_route = "internet", transit_routes = ["10.0.0.0/8"] }
      transit = { cidrs = ["10.60.15.0/28", "10.60.15.16/28", "10.60.15.32/28"], default_route = "nat" }
    }
    nat_gateway_subnets = "public"
    transit_gateway = {
      id                         = "tgw-0123456789abcdef0"
      subnets                    = "transit"
      association_route_table_id = "tgw-rtb-shared"
    }
  }

  assert {
    condition     = length(aws_nat_gateway.nat_gateways) == 3 && length(aws_internet_gateway.internet_gateway) == 1
    error_message = "An egress VPC has an internet gateway and one NAT gateway per zone."
  }

  assert {
    condition     = length(aws_route.transit_routes) == 3
    error_message = "Each public route table sends the internal range back to the Transit Gateway."
  }
}

run "rejects_nat_without_nat_gateway_subnets" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "nat" }
    }
  }

  expect_failures = [var.nat_gateway_subnets]
}

run "rejects_transit_route_without_transit_gateway" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "transit" }
    }
  }

  expect_failures = [var.transit_gateway]
}

run "rejects_wrong_cidr_count" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19"], default_route = "none" }
    }
  }

  expect_failures = [var.subnets]
}

run "rejects_non_generic_name" {
  command = plan

  variables {
    name    = "production-vpc"
    subnets = {}
  }

  expect_failures = [var.name]
}

run "security_defaults" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "none" }
    }
  }

  assert {
    condition     = aws_flow_log.flow_log.traffic_type == "ALL" && aws_flow_log.flow_log.log_destination_type == "cloud-watch-logs"
    error_message = "Every VPC records all its traffic, accepted and rejected, to CloudWatch Logs."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_log.retention_in_days == 365
    error_message = "Flow logs are kept for a year unless the caller says otherwise."
  }

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "The default security group has no rules, so nothing can rely on it."
  }

  assert {
    condition     = jsondecode(local.flow_log_assume_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] != null
    error_message = "Only VPC Flow Logs acting for this account may take the flow log role."
  }
}

run "rejects_unsupported_retention" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "none" }
    }
    flow_log_retention_days = 100
  }

  expect_failures = [var.flow_log_retention_days]
}

run "rejects_zone_not_in_region" {
  command = plan

  # A zone ID from another region, or a typo, fails the plan before anything is built.
  variables {
    availability_zone_ids = ["usw2-az1", "use2-az9"]
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19"], default_route = "none" }
    }
  }

  expect_failures = [aws_vpc.vpc]
}

run "reserved_addresses" {
  command = plan

  variables {
    subnets = {
      ops = { cidrs = ["10.62.228.0/23", "10.62.230.0/23", "10.62.232.0/23"], default_route = "none", reserved_cidrs = ["10.62.228.64/26", "10.62.230.64/26", "10.62.232.64/26"] }
    }
  }

  assert {
    condition     = length(aws_ec2_subnet_cidr_reservation.chosen_addresses) == 3 && aws_ec2_subnet_cidr_reservation.chosen_addresses["ops-usw2-az1"].reservation_type == "explicit"
    error_message = "Each subnet keeps its reserved block for chosen addresses."
  }
}
