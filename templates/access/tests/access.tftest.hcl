mock_provider "aws" {}

variables {
  environment = "staging"
}

run "redis" {
  command = plan

  variables {
    config_dir = "tests/access"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["staging-redis"]) && local.documents["staging-redis"].type == "Session" && local.documents["staging-redis"].content.properties.host == "redis.staging.example.com" && local.documents["staging-redis"].content.properties.portNumber == "10701"
    error_message = "One Session document per file, named <environment>-<file>, with its content as written."
  }
}

run "refuses_shortcuts_and_other_documents" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "redis.yml: keys are document_type, content, as aws_ssm_document takes them, and both are needed"),
      contains(local.problems, "install.yml: document_type is Session; access holds the tunnels people start, and other documents belong in the documents stack"),
    ])
    error_message = "host and port are not arguments, and a Command document is not a tunnel."
  }

  expect_failures = [output.arns]
}
