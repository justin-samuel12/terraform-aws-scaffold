# endpoints.yml turned into endpoints, against a mocked AWS -- docs/endpoints.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc
  values = { id = "vpc-development", cidr_block = "10.42.0.0/16" }
}

override_data {
  target = data.aws_route_tables.route_tables
  values = { ids = ["rtb-private-1", "rtb-data-1", "rtb-ops-1"] }
}

override_data {
  target = data.aws_subnets.tier
  values = { ids = ["subnet-private-1", "subnet-private-2", "subnet-private-3"] }
}

override_data {
  target = module.vpc_endpoint.data.aws_region.current
  values = { region = "us-east-2" }
}

variables {
  config_path = "../../tests/config"
  environment = "development"
  region      = "us-east-2"
}

run "development" {
  command = plan

  variables {
    config_dir = "tests/endpoints"
  }

  assert {
    condition     = toset(local.settings.interface) == toset(["ssm", "ssmmessages", "ec2messages"]) && toset(local.settings.gateway) == toset(["s3"])
    error_message = "The file asks for Session Manager's endpoints and S3."
  }

  assert {
    condition     = toset(keys(output.ids)) == toset(["ssm", "ssmmessages", "ec2messages", "s3"])
    error_message = "One endpoint per service in the file."
  }
}

run "refuses_a_tier_the_vpc_lacks" {
  command = plan

  variables {
    config_dir = "tests/bad-tier"
  }

  expect_failures = [output.ids]
}
