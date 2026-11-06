mock_provider "aws" {}

variables {
  repositories = {
    gitops = {
      lifecycle_policy  = "{\"rules\":[{\"rulePriority\":1,\"selection\":{\"tagStatus\":\"untagged\",\"countType\":\"sinceImagePushed\",\"countUnit\":\"days\",\"countNumber\":14},\"action\":{\"type\":\"expire\"}}]}"
      repository_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
    homekit = {}
  }
  replication_configuration = {
    rule = [{ destination = [{ region = "us-west-2", registry_id = "111111111111" }] }]
  }
}

run "repositories" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.repositories : r.image_tag_mutability == "IMMUTABLE" && r.image_scanning_configuration[0].scan_on_push && r.encryption_configuration[0].encryption_type == "AES256"])
    error_message = "Tags are immutable, every push is scanned, images are encrypted."
  }

  assert {
    condition     = toset(keys(aws_ecr_lifecycle_policy.repositories)) == toset(["gitops"]) && toset(keys(aws_ecr_repository_policy.repositories)) == toset(["gitops"])
    error_message = "A repository gets only the policies it is given."
  }

  assert {
    condition     = aws_ecr_replication_configuration.registry[0].replication_configuration[0].rule[0].destination[0].region == "us-west-2"
    error_message = "The registry replicates as configured."
  }
}

run "nothing" {
  command = plan

  variables {
    repositories              = {}
    replication_configuration = null
  }

  assert {
    condition     = length(aws_ecr_repository.repositories) == 0 && length(aws_ecr_replication_configuration.registry) == 0
    error_message = "Nothing given, nothing built."
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    repositories = { GitOps = {} }
  }

  expect_failures = [var.repositories]
}

run "rejects_a_registry_by_name" {
  command = plan

  variables {
    replication_configuration = { rule = [{ destination = [{ region = "us-west-2", registry_id = "shared" }] }] }
  }

  expect_failures = [var.replication_configuration]
}
