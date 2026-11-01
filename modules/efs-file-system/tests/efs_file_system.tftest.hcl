# What the module builds and refuses, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  name               = "sftp"
  kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  subnet_ids         = ["subnet-data-1", "subnet-data-2", "subnet-data-3"]
  security_group_ids = ["sg-efs"]
  access_points      = { uploads = { path = "/uploads", uid = 1001, gid = 1001 } }
}

run "sftp" {
  command = plan

  assert {
    condition     = aws_efs_file_system.file_system.encrypted && aws_efs_file_system.file_system.throughput_mode == "elastic" && aws_efs_file_system.file_system.tags.Backup == "standard"
    error_message = "Encrypted, elastic throughput, and in the backup plan."
  }

  assert {
    condition     = length(aws_efs_mount_target.zones) == 3 && length(aws_efs_access_point.access_points) == 1
    error_message = "A mount target per zone, and the access points asked for."
  }
}

run "rejects_relative_path" {
  command = plan

  variables {
    access_points = { uploads = { path = "uploads", uid = 1001, gid = 1001 } }
  }

  expect_failures = [var.access_points]
}

run "rejects_one_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-data-1"]
  }

  expect_failures = [var.subnet_ids]
}
