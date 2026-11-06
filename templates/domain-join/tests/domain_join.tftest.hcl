mock_provider "aws" {}

variables {
  environment = "staging"
}

run "windows" {
  command = plan

  variables {
    config_dir = "tests/domain-join"
  }

  assert {
    condition     = local.associations["windows"].parameters.DomainName == "aadds.example.com" && local.associations["windows"].targets[0].key == "tag:Domain" && local.associations["windows"].schedule_expression == "rate(1 day)"
    error_message = "One association per file, with its arguments as written."
  }
}

run "nothing_without_files" {
  command = plan

  variables {
    config_dir = "tests/none"
  }

  assert {
    condition     = output.domain_join.document_name == null && output.domain_join.association_ids == {}
    error_message = "With no files, the stack builds nothing."
  }
}

run "refuses_what_is_not_native" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "everything.yml: keys are targets, parameters, schedule_expression, compliance_severity, max_concurrency, max_errors, as aws_ssm_association takes them"),
      contains(local.problems, "everything.yml: parameters are DomainName and OrganizationalUnit, both needed; SecretId is always the environment's join secret"),
      contains(local.problems, "everything.yml: targets is a list of key (tag:<name>) and values, so only the servers carrying that tag join"),
    ])
    error_message = "Keys that are not the resource's, missing parameters, and targets that are not a tag are each refused."
  }

  expect_failures = [output.domain_join]
}
