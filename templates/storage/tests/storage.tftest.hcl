mock_provider "aws" {}

override_data {
  target = data.aws_vpc.vpc[0]
  values = { id = "vpc-production" }
}

override_data {
  target = data.aws_subnet.subnets["data-az1"]
  values = { id = "subnet-data-1" }
}

override_data {
  target = data.aws_subnet.subnets["data-az2"]
  values = { id = "subnet-data-2" }
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
    condition     = toset(keys(output.file_systems)) == toset(["sftp"]) && toset(keys(output.file_systems.sftp.access_point_ids)) == toset(["uploads"]) && length(local.problems) == 0
    error_message = "One file system per file, with its access points."
  }

  assert {
    condition     = jsonencode(local.resolved.sftp.mount_targets) == jsonencode({ data-az1 = { subnet_id = "subnet-data-1", security_groups = ["sg-efs"] }, data-az2 = { subnet_id = "subnet-data-2", security_groups = ["sg-efs"] }, subnet-0data3 = { subnet_id = "subnet-0data3", security_groups = ["sg-0efs"] } })
    error_message = "Subnets and groups are named and found; ids pass through."
  }

  assert {
    condition     = local.resolved.sftp.tags.Backup == "standard" && local.resolved.sftp.access_points.uploads.root_directory.creation_info.permissions == "0750"
    error_message = "Backup and creation_info are what the file writes."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.file_systems == {}
    error_message = "Without files, no file systems."
  }
}

run "refuses_keys_that_are_not_terraform_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "sftp.yml: keys are tags, mount_targets, access_points: aws_efs_file_system's tags, its aws_efs_mount_target and aws_efs_access_point resources")
    error_message = "tier: and security_groups: are not keys."
  }

  expect_failures = [output.file_systems]
}
