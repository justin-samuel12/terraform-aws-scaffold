# What the module builds and refuses, against a mocked AWS -- docs/compute.md.
mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { root_device_name = "/dev/xvda" }
  }
  mock_data "aws_default_tags" {
    defaults = { tags = { Environment = "production", ManagedBy = "terraform" } }
  }
}

variables {
  name               = "orders-api"
  environment        = "production"
  image_id           = "ami-0123456789abcdef0"
  instance_type      = "m6i.large"
  security_group_ids = ["sg-orders-api"]
  instance_profile   = "orders-api"
  kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-data"
  subnet_ids         = ["subnet-private-1", "subnet-private-2", "subnet-private-3"]
  min_size           = 2
  max_size           = 6
  desired_capacity   = 2
  target_group_arns  = ["arn:aws:elasticloadbalancing:us-east-2:111111111111:targetgroup/app-orders-api-ab12/1"]
  target_tracking_configuration = {
    predefined_metric_type = "ASGAverageCPUUtilization"
    target_value           = 50
  }
}

run "scales_behind_its_target_group" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.group.name == "production-orders-api" && aws_autoscaling_group.group.health_check_type == "ELB" && length(aws_autoscaling_group.group.vpc_zone_identifier) == 3
    error_message = "One group across every zone of its tier, healthy only while its load balancer says so."
  }

  assert {
    condition     = aws_launch_template.group.metadata_options[0].http_tokens == "required" && aws_launch_template.group.metadata_options[0].http_put_response_hop_limit == 2 && aws_launch_template.group.metadata_options[0].instance_metadata_tags == "enabled"
    error_message = "Instances get the same metadata settings as fixed servers: IMDSv2, hop limit 2, tags readable."
  }

  assert {
    condition     = aws_launch_template.group.block_device_mappings[0].device_name == "/dev/xvda" && aws_launch_template.group.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "The root disk is the image's own root device, encrypted with the data key."
  }

  assert {
    condition     = aws_launch_template.group.tag_specifications[0].tags.Group == "orders-api" && aws_launch_template.group.tag_specifications[0].tags.Environment == "production" && aws_launch_template.group.tag_specifications[0].tags["PatchGroup"] == "production"
    error_message = "Instances carry the default tags and the group's own, stamped on at launch."
  }

  assert {
    condition     = aws_autoscaling_policy.target_tracking[0].target_tracking_configuration[0].target_value == 50
    error_message = "Target tracking keeps CPU at the chosen value."
  }
}

run "fixed_size_without_target_tracking" {
  command = plan

  variables {
    target_tracking_configuration = null
    target_group_arns             = []
  }

  assert {
    condition     = length(aws_autoscaling_policy.target_tracking) == 0 && aws_autoscaling_group.group.health_check_type == "EC2"
    error_message = "Without target tracking, no policy; without a target group, EC2 health checks."
  }
}

run "refuses_an_image_search" {
  command = plan

  variables {
    image_id = "ubuntu-24.04-*"
  }

  expect_failures = [var.image_id]
}

run "refuses_one_zone" {
  command = plan

  variables {
    subnet_ids = ["subnet-private-1"]
  }

  expect_failures = [var.subnet_ids]
}
