# What the module builds and refuses, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {}

variables {
  environment        = "production"
  group              = "sqlserver"
  image_id           = "ami-0123456789abcdef0"
  security_group_ids = ["sg-sqlserver"]
  kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  protect            = true
  volumes            = { data = { device = "/dev/sdf", size = 1000, iops = 6000, throughput = 500 } }
  members = {
    sqlserver-01 = { subnet_id = "subnet-data-1", subnet = "data-az1", instance_type = "r6i.2xlarge", private_ip = "10.41.192.70", secondary_ips = ["10.41.192.71", "10.41.192.72"] }
    sqlserver-02 = { subnet_id = "subnet-data-2", subnet = "data-az2", instance_type = "r6i.2xlarge", private_ip = "10.41.196.70", secondary_ips = ["10.41.196.71", "10.41.196.72"] }
  }
}

run "protected_sql_nodes" {
  command = plan

  assert {
    condition     = length(aws_instance.protected) == 2 && length(aws_instance.standard) == 0 && aws_instance.protected["sqlserver-01"].disable_api_termination
    error_message = "Protected servers: termination and stop protection, in the block no plan may destroy."
  }

  assert {
    condition     = aws_instance.protected["sqlserver-01"].metadata_options[0].http_tokens == "required" && !aws_instance.protected["sqlserver-01"].associate_public_ip_address
    error_message = "IMDSv2 only, and no public address."
  }

  assert {
    condition     = aws_instance.protected["sqlserver-01"].private_ip == "10.41.192.70" && length(aws_instance.protected["sqlserver-01"].secondary_private_ips) == 2
    error_message = "The chosen primary, cluster and listener addresses."
  }

  assert {
    condition     = aws_instance.protected["sqlserver-02"].tags["Patch Group"] == "production" && aws_instance.protected["sqlserver-02"].tags.Backup == "standard" && aws_instance.protected["sqlserver-02"].tags.Subnet == "data-az2"
    error_message = "Patched with the environment, backed up, and tagged with its subnet."
  }

  assert {
    condition     = length(aws_ebs_volume.protected) == 2 && alltrue([for v in aws_ebs_volume.protected : v.encrypted])
    error_message = "Each server's data disk is encrypted and protected like the server."
  }

  assert {
    condition     = alltrue([for a in aws_volume_attachment.volumes : !a.force_detach])
    error_message = "A protected server's disks are never forced off."
  }
}

run "disposable_runners" {
  command = plan

  variables {
    group   = "gitrunner"
    protect = false
    volumes = {
      cache = { device = "/dev/sdf", size = 100 }
    }
    members = {
      gitrunner-01 = { subnet_id = "subnet-ops-1", subnet = "ops-az1", instance_type = "c6i.large" }
    }
  }

  assert {
    condition     = length(aws_instance.standard) == 1 && length(aws_instance.protected) == 0
    error_message = "Unprotected servers can be replaced or removed by a plan."
  }

  assert {
    condition     = aws_volume_attachment.volumes["gitrunner-01/cache"].force_detach
    error_message = "A disposable server's disks are forced off, so a rebuild cannot wait on a mounted disk."
  }
}

run "rejects_image_search" {
  command = plan

  variables {
    image_id = "ubuntu2404-app-standard-*"
  }

  expect_failures = [var.image_id]
}
