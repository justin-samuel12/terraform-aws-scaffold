# ecr.yml turned into repositories, against a mocked AWS -- docs/global.md.
mock_provider "aws" {}

override_data {
  target = module.ecr_repository.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

variables {
  config_path = "../../tests/config"
  region      = "us-east-2"
}

run "repositories_and_replication" {
  command = plan

  variables {
    config_dir = "tests/repositories"
  }

  assert {
    condition     = local.repositories == toset(["gitops", "homekit"]) && local.settings.keep_images == 20
    error_message = "The file lists the repositories and how many images to keep."
  }

  assert {
    condition     = local.replicate_to == toset(["us-west-2"])
    error_message = "Ohio's repositories are copied to Oregon."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.urls == {}
    error_message = "Without ecr.yml, no repositories."
  }
}

run "other_accounts_pull" {
  command = plan

  # Production takes the global account (444...); the hub and operations have their own (111...).
  variables {
    region      = "us-east-2"
    config_path = "../../tests/stacks"
  }

  assert {
    condition     = local.pull_accounts == toset(["444444444444"])
    error_message = "Every other environment account may pull, and only those."
  }
}
