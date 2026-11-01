# The environment's patching, against a mocked AWS -- docs/systems-manager.md.
mock_provider "aws" {}

run "defaults" {
  command = plan

  variables {
    environment = "development"
  }

  assert {
    condition     = output.patch_group == "development" && local.settings.approve_after_days == 7
    error_message = "Instances tagged Patch Group = development are patched; patches wait a week."
  }
}
