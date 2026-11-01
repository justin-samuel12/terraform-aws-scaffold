# What the module builds and refuses, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  repositories = ["gitops", "homekit"]
  replicate_to = ["us-west-2"]
}

run "repositories" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.repositories : r.image_tag_mutability == "IMMUTABLE" && r.image_scanning_configuration[0].scan_on_push])
    error_message = "Tags are immutable and every push is scanned."
  }

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.repositories["gitops"].policy).rules) == 2
    error_message = "Untagged images expire, and only the newest tagged ones are kept."
  }

  assert {
    condition     = aws_ecr_replication_configuration.registry[0].replication_configuration[0].rule[0].destination[0].region == "us-west-2"
    error_message = "Every repository is copied to the other region."
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    repositories = ["GitOps"]
  }

  expect_failures = [var.repositories]
}
