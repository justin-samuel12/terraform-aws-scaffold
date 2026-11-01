# Tunnel files turned into Session Manager documents, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

run "redis" {
  command = plan

  variables {
    environment = "staging"
    config_dir  = "tests/access"
  }

  assert {
    condition     = local.documents["staging-redis"].content.properties.host == "redis.staging.example.com" && local.documents["staging-redis"].content.properties.portNumber == "10701"
    error_message = "One tunnel document per file, to its fixed host and port, named <environment>-<file>."
  }
}
