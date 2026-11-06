mock_provider "aws" {}

run "one_document" {
  command = plan

  variables {
    config_dir = "tests/documents"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["install-cloudwatch-agent"]) && local.documents["install-cloudwatch-agent"].type == "Command" && local.documents["install-cloudwatch-agent"].content.mainSteps[0].inputs.documentPath == "AWS-ConfigureAWSPackage"
    error_message = "One document per file, named after it, with its document_type and content as written."
  }
}

run "refuses_keys_that_are_not_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition     = contains(local.problems, "hello.yml: keys are document_type, content, as aws_ssm_document takes them, and both are needed")
    error_message = "type and steps are not arguments of aws_ssm_document."
  }

  expect_failures = [output.arns]
}
