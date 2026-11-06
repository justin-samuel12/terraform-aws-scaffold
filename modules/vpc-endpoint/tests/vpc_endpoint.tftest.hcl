mock_provider "aws" {}

variables {
  vpc_id = "vpc-0123456789abcdef0"
  endpoints = {
    ssm = { service_name = "com.amazonaws.us-east-2.ssm", vpc_endpoint_type = "Interface", subnet_ids = ["subnet-a", "subnet-b", "subnet-c"], security_group_ids = ["sg-endpoints"], private_dns_enabled = true }
    s3  = { service_name = "com.amazonaws.us-east-2.s3", vpc_endpoint_type = "Gateway", route_table_ids = ["rtb-1", "rtb-2"] }
  }
}

run "interface_and_gateway" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.endpoints["ssm"].service_name == "com.amazonaws.us-east-2.ssm" && aws_vpc_endpoint.endpoints["ssm"].private_dns_enabled && toset(aws_vpc_endpoint.endpoints["ssm"].security_group_ids) == toset(["sg-endpoints"]) && toset(aws_vpc_endpoint.endpoints["ssm"].subnet_ids) == toset(["subnet-a", "subnet-b", "subnet-c"])
    error_message = "An Interface endpoint takes the subnets, groups and private DNS it was given."
  }

  assert {
    condition     = aws_vpc_endpoint.endpoints["s3"].vpc_endpoint_type == "Gateway" && toset(aws_vpc_endpoint.endpoints["s3"].route_table_ids) == toset(["rtb-1", "rtb-2"])
    error_message = "A Gateway endpoint is on the route tables it was given."
  }

  assert {
    condition     = aws_vpc_endpoint.endpoints["s3"].tags.Name == "s3"
    error_message = "An endpoint is named for its key."
  }
}

run "rejects_one_zone" {
  command = plan

  variables {
    endpoints = { ssm = { service_name = "com.amazonaws.us-east-2.ssm", vpc_endpoint_type = "Interface", subnet_ids = ["subnet-a"], security_group_ids = ["sg-endpoints"], private_dns_enabled = true } }
  }

  expect_failures = [var.endpoints]
}

run "rejects_a_short_service_name" {
  command = plan

  variables {
    endpoints = { s3 = { service_name = "s3", vpc_endpoint_type = "Gateway", route_table_ids = ["rtb-1"] } }
  }

  expect_failures = [var.endpoints]
}
