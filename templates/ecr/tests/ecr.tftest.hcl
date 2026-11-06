mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  config_path = "../../tests/stacks"
  region      = "us-east-2"
}

run "repositories_and_replication" {
  command = plan

  variables {
    config_dir = "tests/repositories"
  }

  assert {
    condition     = toset(keys(local.built)) == toset(["gitops", "homekit"]) && length(local.problems) == 0
    error_message = "One repository per file, named after the file."
  }

  assert {
    condition     = jsondecode(local.built.gitops.lifecycle_policy).rules[1].selection.countNumber == 20 && local.built.homekit.lifecycle_policy == null
    error_message = "A lifecycle policy is the file's own rules; a file without one gets none."
  }

  assert {
    condition     = jsonencode(jsondecode(local.built.gitops.repository_policy).Statement[0].Principal.AWS) == jsonencode(["arn:aws:iam::444444444444:root", "222222222222"])
    error_message = "An environment's name stands for its account; an account ID passes through."
  }

  assert {
    condition     = local.replication.rule[0].destination[0].registry_id == "111111111111"
    error_message = "shared stands for this region's hub account."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.urls == {} && local.replication == null
    error_message = "Without files, nothing: no repositories and no replication."
  }
}

run "refusals" {
  command = plan

  variables {
    config_dir = "tests/refused"
  }

  assert {
    condition = alltrue([for p in [
      "ecr.yml: keys are tags, lifecycle_policy, repository_policy",
      "runner.yml: keys are tags, lifecycle_policy, repository_policy",
      "runner.yml: Principal AWS staging is not an account ID",
      "replication-configuration/: the registry has one replication configuration",
    ] : length([for q in local.problems : q if startswith(q, p)]) == 1])
    error_message = "An old settings file, a key that is not an argument, an unknown environment and two replication files are each refused."
  }

  expect_failures = [output.urls]
}
