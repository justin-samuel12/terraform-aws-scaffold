# What the module builds and refuses, against a mocked AWS -- docs/endpoints.md.
mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2" }
}

variables {
  vpc_id          = "vpc-0123456789abcdef0"
  vpc_cidr        = "10.42.0.0/16"
  interface       = ["ssm", "ssmmessages", "ec2messages"]
  gateway         = ["s3"]
  subnet_ids      = ["subnet-a", "subnet-b", "subnet-c"]
  route_table_ids = ["rtb-1", "rtb-2"]
}

run "ssm_and_s3" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ssm", "ssmmessages", "ec2messages"]) && aws_vpc_endpoint.interface["ssm"].service_name == "com.amazonaws.us-east-2.ssm"
    error_message = "Session Manager needs the ssm, ssmmessages and ec2messages interface endpoints."
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled])
    error_message = "Interface endpoints answer at the service's usual name, so agents need no settings."
  }

  assert {
    condition     = aws_vpc_endpoint.gateway["s3"].vpc_endpoint_type == "Gateway" && length(aws_vpc_endpoint.gateway["s3"].route_table_ids) == 2
    error_message = "S3 is a gateway endpoint on every route table."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints[0].cidr_ipv4 == "10.42.0.0/16" && aws_vpc_security_group_ingress_rule.endpoints[0].from_port == 443
    error_message = "Only HTTPS from inside the VPC reaches the interface endpoints."
  }
}

run "gateway_only_needs_no_security_group" {
  command = plan

  variables {
    interface = []
  }

  assert {
    condition     = length(aws_security_group.endpoints) == 0
    error_message = "No interface endpoints, no security group."
  }
}

run "rejects_unknown_gateway" {
  command = plan

  variables {
    gateway = ["ssm"]
  }

  expect_failures = [var.gateway]
}

run "rejects_one_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-a"]
  }

  expect_failures = [aws_vpc_endpoint.interface]
}
