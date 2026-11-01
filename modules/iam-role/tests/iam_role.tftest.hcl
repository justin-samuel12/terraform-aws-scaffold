# What the module builds and refuses, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  policies = {
    read-tags = {
      description = "Read instance tags, for service discovery"
      statements  = [{ actions = ["ec2:DescribeTags"], resources = ["*"] }]
    }
  }
  roles = {
    grafana = {
      description      = "Grafana servers"
      services         = ["ec2"]
      managed_policies = ["AmazonSSMManagedInstanceCore"]
      policies         = ["read-tags"]
      statements       = [{ actions = ["ec2:DescribeInstances"], resources = ["*"] }]
    }
  }
}

run "instance_role" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.roles["grafana"].assume_role_policy).Statement[0].Principal.Service == ["ec2.amazonaws.com"]
    error_message = "Only the named service may assume the role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.managed["grafana/AmazonSSMManagedInstanceCore"].policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "AWS managed policies are attached by name."
  }

  assert {
    condition     = length(aws_iam_instance_profile.profiles) == 1
    error_message = "A role EC2 assumes gets an instance profile."
  }

  assert {
    condition     = aws_iam_policy.policies["read-tags"].name == "read-tags" && contains(keys(aws_iam_role_policy_attachment.policies), "grafana/read-tags")
    error_message = "A shared policy is created once and attached to each role naming it."
  }
}

run "rejects_unknown_policy" {
  command = plan

  variables {
    roles = {
      grafana = { description = "Grafana servers", services = ["ec2"], policies = ["missing"] }
    }
  }

  expect_failures = [var.roles]
}

run "rejects_policy_allowing_everything" {
  command = plan

  variables {
    policies = {
      admin = { description = "Too much", statements = [{ actions = ["*"], resources = ["*"] }] }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_everything_on_everything" {
  command = plan

  variables {
    roles = {
      admin = { description = "Too much", services = ["ec2"], statements = [{ actions = ["*"], resources = ["*"] }] }
    }
  }

  expect_failures = [var.roles]
}
