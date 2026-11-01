# Database files turned into databases, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-development" }
}

override_data {
  target = data.aws_subnets.data[0]
  values = { ids = ["subnet-data-1", "subnet-data-2", "subnet-data-3"] }
}

override_data {
  target = data.aws_security_group.groups["database-mysql"]
  values = { id = "sg-database-mysql" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = module.monitoring_role[0].data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "development"
}

run "zabbix" {
  command = plan

  variables {
    config_dir = "tests/databases"
  }

  assert {
    condition     = toset(keys(output.databases)) == toset(["zabbix"])
    error_message = "One database per file."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.databases == {}
    error_message = "Without files, no databases and no monitoring role."
  }
}
