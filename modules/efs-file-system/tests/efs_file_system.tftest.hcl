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
  name        = "sftp"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  tags        = { Backup = "standard" }
  mount_targets = {
    data-az1 = { subnet_id = "subnet-data-1", security_groups = ["sg-efs"] }
    data-az2 = { subnet_id = "subnet-data-2", security_groups = ["sg-efs"] }
    data-az3 = { subnet_id = "subnet-data-3", security_groups = ["sg-efs"] }
  }
  access_points = {
    uploads = {
      posix_user     = { uid = 1001, gid = 1001 }
      root_directory = { path = "/uploads", creation_info = { owner_uid = 1001, owner_gid = 1001, permissions = "0750" } }
    }
  }
}

run "sftp" {
  command = plan

  assert {
    condition     = aws_efs_file_system.file_system.encrypted && aws_efs_file_system.file_system.throughput_mode == "elastic" && aws_efs_file_system.file_system.tags.Backup == "standard"
    error_message = "Encrypted, elastic throughput, with the tags it was given."
  }

  assert {
    condition     = length(aws_efs_mount_target.zones) == 3 && toset(aws_efs_mount_target.zones["data-az2"].security_groups) == toset(["sg-efs"]) && length(aws_efs_access_point.access_points) == 1
    error_message = "The mount targets and access points asked for."
  }

  assert {
    condition     = one(one(aws_efs_access_point.access_points["uploads"].root_directory).creation_info).permissions == "0750"
    error_message = "creation_info is what it was given."
  }
}

run "no_creation_info" {
  command = plan

  variables {
    access_points = { uploads = { posix_user = { uid = 1001, gid = 1001 }, root_directory = { path = "/uploads" } } }
  }

  assert {
    condition     = length(one(aws_efs_access_point.access_points["uploads"].root_directory).creation_info) == 0
    error_message = "Without creation_info, the directory is not created."
  }
}

run "rejects_relative_path" {
  command = plan

  variables {
    access_points = { uploads = { posix_user = { uid = 1001, gid = 1001 }, root_directory = { path = "uploads" } } }
  }

  expect_failures = [var.access_points]
}

run "rejects_one_zone" {
  command = plan

  variables {
    mount_targets = { data-az1 = { subnet_id = "subnet-data-1", security_groups = ["sg-efs"] } }
  }

  expect_failures = [var.mount_targets]
}
