# The environment's keys, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = module.kms_key.data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = module.kms_key.data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.kms_key.data.aws_region.current
  values = { region = "us-east-2" }
}

variables {
  config_path = "../../tests/config"
}

run "operations" {
  command = plan

  variables {
    environment = "operations"
    region      = "us-east-2"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["data", "backup"]) && local.replica_regions == toset(["us-west-2"])
    error_message = "A data key and a backup key, each replicated to Oregon."
  }
}
