# What the module builds and refuses, against a mocked AWS -- docs/security-groups.md.
mock_provider "aws" {}

variables {
  lists = {
    staff-team = [
      { cidr = "10.10.70.0/24", description = "Corporate wired" },
      { cidr = "10.10.80.0/24", description = "Corporate wireless" },
    ]
  }
}

run "staff_team" {
  command = plan

  assert {
    condition     = aws_ec2_managed_prefix_list.lists["staff-team"].name == "staff-team" && length(aws_ec2_managed_prefix_list.lists["staff-team"].entry) == 2
    error_message = "One prefix list per name, with its entries."
  }

  assert {
    condition     = aws_ec2_managed_prefix_list.lists["staff-team"].max_entries == 7
    error_message = "Each list leaves room to grow by five entries."
  }
}

run "rejects_entry_without_description" {
  command = plan

  variables {
    lists = { staff-team = [{ cidr = "10.10.70.0/24", description = "" }] }
  }

  expect_failures = [var.lists]
}
