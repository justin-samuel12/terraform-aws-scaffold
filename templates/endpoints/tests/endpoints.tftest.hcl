mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-operations" }
}

override_data {
  target = data.aws_subnet.subnets["private-az1"]
  values = { id = "subnet-private-1" }
}

override_data {
  target = data.aws_subnet.subnets["private-az2"]
  values = { id = "subnet-private-2" }
}

override_data {
  target = data.aws_subnet.subnets["private-az3"]
  values = { id = "subnet-private-3" }
}

override_data {
  target = data.aws_route_table.route_tables["private-az1"]
  values = { id = "rtb-private-1" }
}

override_data {
  target = data.aws_route_table.route_tables["data-az1"]
  values = { id = "rtb-data-1" }
}

override_data {
  target = data.aws_security_group.groups["endpoints"]
  values = { id = "sg-endpoints" }
}

variables {
  config_path = "../../tests/config"
  environment = "operations"
  region      = "us-east-2"
}

run "operations" {
  command = plan

  variables {
    config_dir = "tests/endpoints"
  }

  assert {
    condition     = toset(keys(output.ids)) == toset(["ssm", "ssmmessages", "ec2messages", "s3"]) && length(local.problems) == 0
    error_message = "One endpoint per file, named after the file."
  }

  assert {
    condition     = jsonencode(local.resolved.ssm.subnet_ids) == jsonencode(["subnet-private-1", "subnet-private-2", "subnet-private-3"]) && jsonencode(local.resolved.ssm.security_group_ids) == jsonencode(["sg-endpoints"])
    error_message = "Subnets and security groups are named, and found by their names."
  }

  assert {
    condition     = jsonencode(local.resolved.s3.route_table_ids) == jsonencode(["rtb-private-1", "rtb-data-1", "rtb-0ops"])
    error_message = "A route table is named for its subnet; an id passes through."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "endpoints.yml: keys are service_name, vpc_endpoint_type, subnet_ids, security_group_ids, private_dns_enabled, route_table_ids, tags, as aws_vpc_endpoint takes them")
    error_message = "The old settings file is refused."
  }

  expect_failures = [output.ids]
}

run "refuses_a_subnet_the_vpc_lacks" {
  command = plan

  variables {
    config_dir = "tests/bad-subnet"
  }

  assert {
    condition     = length([for p in local.problems : p if startswith(p, "ssm.yml: public-az1 is not a subnet of operations's VPC in us-east-2")]) == 1
    error_message = "operations has no public tier."
  }

  expect_failures = [output.ids]
}
