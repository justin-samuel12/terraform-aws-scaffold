# Document files turned into SSM documents, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

run "one_document" {
  command = plan

  variables {
    config_dir = "tests/documents"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["install-cloudwatch-agent"])
    error_message = "One document per file."
  }
}
