mock_provider "aws" {}

variables {
  name = "tgw-peering-01"
  requester = {
    region             = "us-west-2"
    transit_gateway_id = "tgw-oregon"
    route_table_id     = "tgw-rtb-oregon-shared"
    routes = {
      restricted = { route_table_id = "tgw-rtb-oregon-restricted", cidrs = ["10.41.0.0/16"] }
      shared     = { route_table_id = "tgw-rtb-oregon-shared", cidrs = ["10.40.0.0/20", "10.41.0.0/16"] }
    }
  }
  accepter = {
    region             = "us-east-2"
    transit_gateway_id = "tgw-ohio"
    route_table_id     = "tgw-rtb-ohio-shared"
    routes = {
      restricted = { route_table_id = "tgw-rtb-ohio-restricted", cidrs = ["10.61.0.0/16", "10.63.0.0/16"] }
      shared     = { route_table_id = "tgw-rtb-ohio-shared", cidrs = ["10.60.0.0/20", "10.61.0.0/16", "10.62.0.0/16", "10.63.0.0/16"] }
    }
  }
}

run "peering" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway_peering_attachment.peering_attachment.region == "us-west-2" && aws_ec2_transit_gateway_peering_attachment_accepter.peering_attachment_accepter.region == "us-east-2"
    error_message = "Each side of the peering is created in its own region."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table_association.route_table_associations) == 2
    error_message = "The peering is associated with one route table on each side."
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_route.routes) == 9
    error_message = "One static route per listed CIDR, on both sides."
  }

  assert {
    condition     = aws_ec2_transit_gateway_route.routes["accepter restricted 10.63.0.0/16"].region == "us-east-2"
    error_message = "Routes are created in their own side's region."
  }
}

run "rejects_same_region" {
  command = plan

  variables {
    accepter = {
      region             = "us-west-2"
      transit_gateway_id = "tgw-other"
      route_table_id     = "tgw-rtb-other"
      routes             = {}
    }
  }

  expect_failures = [var.accepter]
}
