mock_provider "aws" {}

variables {
  environment        = "production"
  group              = "sqlserver"
  image_id           = "ami-0123456789abcdef0"
  security_group_ids = ["sg-sqlserver"]
  kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  volumes            = { data = { device = "/dev/sdf", size = 1000, iops = 6000, throughput = 500 } }
  members = {
    sqlserver-01 = { subnet_id = "subnet-data-1", subnet = "data-az1", instance_type = "r6i.2xlarge", private_ip = "10.41.192.70", secondary_ips = ["10.41.192.71", "10.41.192.72"] }
    sqlserver-02 = { subnet_id = "subnet-data-2", subnet = "data-az2", instance_type = "r6i.2xlarge", private_ip = "10.41.196.70", secondary_ips = ["10.41.196.71", "10.41.196.72"] }
  }
}

run "sql_nodes" {
  command = plan

  assert {
    condition     = length(aws_instance.servers) == 2 && aws_instance.servers["sqlserver-01"].disable_api_termination && !aws_instance.servers["sqlserver-01"].disable_api_stop
    error_message = "Every server has termination protection; stop protection stays off so a type change can be made in place."
  }

  assert {
    condition     = aws_instance.servers["sqlserver-01"].metadata_options[0].http_tokens == "required" && aws_instance.servers["sqlserver-01"].metadata_options[0].http_put_response_hop_limit == 2 && aws_instance.servers["sqlserver-01"].metadata_options[0].instance_metadata_tags == "enabled" && !aws_instance.servers["sqlserver-01"].associate_public_ip_address
    error_message = "IMDSv2 only, and no public address."
  }

  assert {
    condition     = aws_instance.servers["sqlserver-01"].private_ip == "10.41.192.70" && length(aws_instance.servers["sqlserver-01"].secondary_private_ips) == 2
    error_message = "The chosen primary, cluster and listener addresses."
  }

  assert {
    condition     = aws_instance.servers["sqlserver-02"].tags["PatchGroup"] == "production" && aws_instance.servers["sqlserver-02"].tags.Backup == "standard" && aws_instance.servers["sqlserver-02"].tags.Subnet == "data-az2"
    error_message = "Patched with the environment, backed up, and tagged with its subnet."
  }

  assert {
    condition     = length(aws_ebs_volume.volumes) == 2 && alltrue([for v in aws_ebs_volume.volumes : v.encrypted])
    error_message = "Each server's data disk is encrypted and protected like the server."
  }

}

run "runners" {
  command = plan

  variables {
    group   = "runner"
    volumes = {}
    members = {
      runner-01 = { subnet_id = "subnet-ops-1", subnet = "ops-az1", instance_type = "c6i.large" }
    }
  }

  assert {
    condition     = aws_instance.servers["runner-01"].disable_api_termination && length(aws_ebs_volume.volumes) == 0
    error_message = "A server with no state is protected the same way: there is one kind of server."
  }
}

run "rejects_image_search" {
  command = plan

  variables {
    image_id = "ubuntu2404-app-standard-*"
  }

  expect_failures = [var.image_id]
}

run "tags_merge" {
  command = plan

  variables {
    tags = { BackupTier = "Daily", Function = "group-wide", Certificates = "['staging.example.com']" }
    members = {
      sqlserver-01 = { subnet_id = "subnet-data-1", subnet = "data-az1", instance_type = "r6i.2xlarge", tags = { Function = "sql01", DNS = "sql01", Group = "mine", Name = "mine" } }
      sqlserver-02 = { subnet_id = "subnet-data-2", subnet = "data-az2", instance_type = "r6i.2xlarge" }
    }
  }

  assert {
    condition     = aws_instance.servers["sqlserver-01"].tags.Function == "sql01" && aws_instance.servers["sqlserver-01"].tags.DNS == "sql01" && aws_instance.servers["sqlserver-01"].tags.BackupTier == "Daily" && aws_instance.servers["sqlserver-02"].tags.Function == "group-wide"
    error_message = "A server's own tags win over the group's; a server without any keeps the group's."
  }

  assert {
    condition     = aws_instance.servers["sqlserver-01"].tags.Name == "sqlserver-01" && aws_instance.servers["sqlserver-01"].tags.Server == "sqlserver-01" && aws_instance.servers["sqlserver-01"].tags.Group == "sqlserver"
    error_message = "The tags the module sets itself win over any server's."
  }
}
