# Function files turned into functions; AWS is mocked, the code is zipped for real -- docs/global.md.
mock_provider "aws" {}

run "hello" {
  command = plan

  variables {
    config_dir = "tests/functions"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["hello"])
    error_message = "One function per file, built from src/<name>/."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without files, no functions."
  }
}
