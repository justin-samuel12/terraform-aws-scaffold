mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = { zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3", "usw2-az4"] }
}

variables {
  cidr_block            = "10.62.0.0/16"
  availability_zone_ids = ["usw2-az1", "usw2-az2", "usw2-az3"]
}

run "spoke" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "staging" } }
  }

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
    condition     = aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment[0].transit_gateway_default_route_table_association == false
    error_message = "On this account's own gateway the attachment stays out of the default route table; on one shared through RAM the setting is left to its owner."
  }

  assert {
    condition     = aws_subnet.subnets["data-usw2-az2"].tags.Name == "Staging - Data Subnet AZ2" && aws_subnet.subnets["data-usw2-az2"].tags.Subnet == "data-az2" && aws_subnet.subnets["data-usw2-az2"].tags.Tier == "data"
    error_message = "A subnet's Name tag is the environment, its tier and its zone; its Subnet tag is what stacks find it by."
  }

  assert {
    condition     = aws_vpc.vpc.tags.Name == "Staging - VPC" && aws_route_table.route_tables["private-usw2-az1"].tags.Name == "Staging - Private Route Table AZ1" && aws_route_table.route_tables["private-usw2-az1"].tags.Subnet == "private-az1"
    error_message = "The VPC and its route tables are named for the console, with the environment first."
  }
}

run "another_accounts_gateway" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "transit" }
      transit = { cidrs = ["10.62.252.0/28", "10.62.252.16/28", "10.62.252.32/28"], default_route = "none" }
    }
    transit_gateway = {
      id                         = "tgw-0123456789abcdef0"
      subnets                    = "transit"
      association_route_table_id = "tgw-rtb-standard"
      route_here                 = false
      shared                     = true
    }
    transit_gateway_accepted = "tgw-attach-accepted"
  }

  assert {
    condition     = terraform_data.transit_gateway_accepted[0].input == "tgw-attach-accepted" && length(aws_ec2_transit_gateway_route_table_association.route_table_association) == 0
    error_message = "Routes to the gateway wait for its owner to accept the attachment, and the owner associates it, not this account."
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

  assert {
    condition     = aws_nat_gateway.nat_gateways["usw2-az2"].tags.Name == "NAT Gateway AZ2" && aws_eip.eips["usw2-az2"].tags.Name == "NAT Gateway AZ2 Address" && aws_subnet.subnets["public-usw2-az1"].tags.Name == "Public Subnet AZ1"
    error_message = "Without an Environment default tag, a Name is only what the thing is."
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

run "peered" {
  command = plan

  variables {
    cidr_block = "10.63.0.0/16"
    subnets = {
      public  = { cidrs = ["10.63.216.0/23", "10.63.218.0/23", "10.63.220.0/23"], default_route = "none" }
      private = { cidrs = ["10.63.0.0/19", "10.63.32.0/19", "10.63.64.0/19"], default_route = "none" }
      data    = { cidrs = ["10.63.192.0/22", "10.63.196.0/22", "10.63.200.0/22"], default_route = "none" }
    }
    nat_gateway_subnets = "public"
    routes = {
      public-internet  = { tier = "public", destination_cidr_block = "0.0.0.0/0", gateway_id = "own" }
      private-internet = { tier = "private", destination_cidr_block = "0.0.0.0/0", nat_gateway_id = "own" }
      private-ops      = { tier = "private", destination_cidr_block = "10.42.0.0/16", vpc_peering_connection_id = "pcx-0123456789abcdef0" }
      data-ops         = { tier = "data", destination_cidr_block = "10.42.0.0/16", vpc_peering_connection_id = "pcx-0123456789abcdef0" }
    }
    network_acls = {
      data = {
        ingress = [
          { rule_no = 100, action = "allow", protocol = "-1", cidr_block = "10.0.0.0/8" },
          { rule_no = 200, action = "deny", protocol = "-1", cidr_block = "0.0.0.0/0" },
        ]
        egress = [
          { rule_no = 100, action = "allow", protocol = "-1", cidr_block = "10.0.0.0/8" },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_internet_gateway.internet_gateway) == 1 && length(aws_nat_gateway.nat_gateways) == 3 && length(aws_ec2_transit_gateway_vpc_attachment.transit_gateway_vpc_attachment) == 0
    error_message = "A VPC off the hub has its own internet gateway and a NAT gateway per zone, and no attachment."
  }

  assert {
    condition     = length(aws_route.routes) == 12 && aws_route.routes["private-usw2-az2-10.42.0.0/16"].vpc_peering_connection_id == "pcx-0123456789abcdef0" && length(aws_route.default_routes) == 0 && length(aws_route.transit_routes) == 0
    error_message = "Each route goes in every route table of its tier, and only the routes written are made."
  }

  assert {
    condition     = toset(keys(aws_network_acl.network_acls)) == toset(["data"]) && aws_network_acl.network_acls["data"].tags.Tier == "data"
    error_message = "A network ACL covers every subnet of its tier, with the rules written; other tiers keep the default."
  }
}

run "rejects_a_route_with_two_targets" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "none" }
    }
    routes = {
      both = { tier = "private", destination_cidr_block = "10.42.0.0/16", vpc_peering_connection_id = "pcx-1", transit_gateway_id = "tgw-1" }
    }
  }

  expect_failures = [var.routes]
}

run "rejects_nat_without_nat_gateways" {
  command = plan

  variables {
    subnets = {
      private = { cidrs = ["10.62.0.0/19", "10.62.32.0/19", "10.62.64.0/19"], default_route = "none" }
    }
    routes = {
      out = { tier = "private", destination_cidr_block = "0.0.0.0/0", nat_gateway_id = "own" }
    }
  }

  expect_failures = [var.nat_gateway_subnets]
}

run "rejects_a_repeated_rule_number" {
  command = plan

  variables {
    subnets = {
      data = { cidrs = ["10.62.192.0/22", "10.62.196.0/22", "10.62.200.0/22"], default_route = "none" }
    }
    network_acls = {
      data = {
        ingress = [
          { rule_no = 100, action = "allow", protocol = "-1", cidr_block = "10.0.0.0/8" },
          { rule_no = 100, action = "deny", protocol = "-1", cidr_block = "0.0.0.0/0" },
        ]
      }
    }
  }

  expect_failures = [var.network_acls]
}
