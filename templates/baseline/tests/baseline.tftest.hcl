mock_provider "aws" {}

variables {
  config_path = "../../tests/config"
}

run "every_region_in_config" {
  command = plan

  variables {
    region = "us-east-2"
  }

  assert {
    condition     = output.regions == toset(["us-east-2", "us-west-2"])
    error_message = "Both regions in config/ get EBS encryption and an access analyzer."
  }
}
