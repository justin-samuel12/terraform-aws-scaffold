# File system files turned into file systems, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-production" }
}

override_data {
  target = data.aws_subnets.tiers["data"]
  values = { ids = ["subnet-data-1", "subnet-data-2", "subnet-data-3"] }
}

override_data {
  target = data.aws_security_group.groups["accesscontrol-efs"]
  values = { id = "sg-efs" }
}

override_data {
  target = data.aws_kms_key.data[0]
  values = { arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data" }
}

override_data {
  target = module.efs_file_system["sftp"].data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.efs_file_system["sftp"].data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "production"
}

run "sftp" {
  command = plan

  variables {
    config_dir = "tests/storage"
  }

  assert {
    condition     = toset(keys(output.file_systems)) == toset(["sftp"]) && toset(keys(output.file_systems.sftp.access_point_ids)) == toset(["uploads"])
    error_message = "One file system per file, with its access points."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.file_systems == {}
    error_message = "Without files, no file systems."
  }
}
