mock_provider "aws" {}

variables {
  name            = "tgw-01"
  amazon_side_asn = 64512
  route_tables    = ["restricted", "standard", "shared"]
}

run "hub" {
  command = plan

  override_data {
    target = data.aws_default_tags.current
    values = { tags = { Environment = "shared" } }
  }

  variables {
    routes = {
      restricted-default = { route_table = "restricted", destination = "0.0.0.0/0", attachment_id = "tgw-attach-egress" }
      standard-default   = { route_table = "standard", destination = "0.0.0.0/0", attachment_id = "tgw-attach-egress" }
      standard-no-prod   = { route_table = "standard", destination = "10.41.0.0/16", blackhole = true }
    }
  }

  assert {
    condition     = aws_ec2_transit_gateway.transit_gateway.default_route_table_association == "disable" && aws_ec2_transit_gateway.transit_gateway.default_route_table_propagation == "disable"
    error_message = "Attachments must choose their route table; nothing joins one by default."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.route_tables) == 3 && aws_ec2_transit_gateway_route_table.route_tables["restricted"].tags.Name == "Shared - Transit Gateway Restricted" && aws_ec2_transit_gateway_route_table.route_tables["restricted"].tags.Segment == "restricted"
    error_message = "One route table per isolation level, named for the console and found by its Segment tag."
  }

  assert {
    condition     = aws_ec2_transit_gateway.transit_gateway.tags.Name == "Shared - Transit Gateway"
    error_message = "The Transit Gateway's Name tag is its environment, then what it is."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route.routes["standard-no-prod"].blackhole
    error_message = "A blackhole route drops traffic for its destination."
  }

  assert {
    condition     = aws_ec2_transit_gateway.transit_gateway.security_group_referencing_support == "disable"
    error_message = "Security groups cannot reference each other across VPCs unless asked for."
  }
}

run "security_group_referencing" {
  command = plan

  variables {
    security_group_referencing = true
  }

  assert {
    condition     = aws_ec2_transit_gateway.transit_gateway.security_group_referencing_support == "enable"
    error_message = "Turned on, VPCs attached to the hub may reference each other's security groups."
  }
}

run "rejects_unknown_route_table" {
  command = plan

  variables {
    routes = { stray = { route_table = "production", destination = "0.0.0.0/0", attachment_id = "tgw-attach-egress" } }
  }

  expect_failures = [var.routes]
}

run "rejects_route_with_both_targets" {
  command = plan

  variables {
    routes = { both = { route_table = "shared", destination = "0.0.0.0/0", attachment_id = "tgw-attach-egress", blackhole = true } }
  }

  expect_failures = [var.routes]
}

run "rejects_public_asn" {
  command = plan

  variables {
    amazon_side_asn = 16509
  }

  expect_failures = [var.amazon_side_asn]
}
