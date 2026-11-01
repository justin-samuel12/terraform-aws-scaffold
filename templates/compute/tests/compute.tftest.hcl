# Group files turned into placed, addressed servers, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-development" }
}

override_data {
  target = data.aws_security_group.groups["sqlserver"]
  values = { id = "sg-sqlserver" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["sqlserver"]
  values = { name = "sqlserver" }
}

override_data {
  target = data.aws_iam_instance_profile.profiles["gitrunner"]
  values = { name = "gitrunner" }
}

variables {
  config_path = "../../tests/config"
  environment = "development"
  region      = "us-east-2"
}

run "placement_and_addresses" {
  command = plan

  variables {
    config_dir = "tests/groups"
  }

  assert {
    condition     = local.servers["sqlserver-01"].addresses.primary == "10.42.192.70" && local.servers["sqlserver-02"].addresses.listener == "10.42.196.72"
    error_message = "Host numbers become addresses in each server's subnet: 10.<env>.<subnet>.70."
  }

  assert {
    condition     = [for n in ["gitrunner-01", "gitrunner-02", "gitrunner-03"] : local.servers[n].subnet] == ["ops-az1", "ops-az2", "ops-az3"]
    error_message = "Unpinned servers spread across the zones in turn."
  }

  assert {
    condition     = local.servers["gitrunner-01"].addresses == {}
    error_message = "A server without ip: gets an address from AWS."
  }
}

run "refuses_an_address_outside_the_reserved_block" {
  command = plan

  variables {
    config_dir = "tests/bad-ip"
  }

  expect_failures = [output.servers]
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.servers == {}
    error_message = "Without files, no servers."
  }
}

run "refuses_a_group_without_a_role" {
  command = plan

  variables {
    config_dir = "tests/no-role"
  }

  expect_failures = [output.servers]
}
