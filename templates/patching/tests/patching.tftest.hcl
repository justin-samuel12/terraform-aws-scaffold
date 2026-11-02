# The environment's patching, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

run "defaults" {
  command = plan

  variables {
    environment = "operations"
  }

  assert {
    condition     = output.patch_group == "operations" && local.settings.approve_after_days == 7
    error_message = "Instances tagged Patch Group = operations are patched; patches wait a week."
  }
}
