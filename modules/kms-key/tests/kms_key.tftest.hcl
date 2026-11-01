# What the module builds and refuses, against a mocked AWS -- docs/data.md.
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-2" }
}

variables {
  environment     = "development"
  purposes        = { data = ["rds", "elasticfilesystem"], backup = ["backup"] }
  replica_regions = ["us-west-2"]
}

run "keys_and_replicas" {
  command = plan

  assert {
    condition     = alltrue([for k in aws_kms_key.keys : k.enable_key_rotation && k.deletion_window_in_days == 30 && k.multi_region])
    error_message = "Rotated yearly, 30 days to undo a deletion, and multi-Region."
  }

  assert {
    condition     = aws_kms_alias.keys["data"].name == "alias/development-data" && length(aws_kms_replica_key.replicas) == 2
    error_message = "One alias per purpose, and each key replicated to Oregon."
  }

  assert {
    condition     = contains(jsondecode(local.policies["data"]).Statement[1].Condition.StringEquals["kms:ViaService"], "rds.us-west-2.amazonaws.com")
    error_message = "Only the named services may use the key, in its regions, for this account."
  }

  assert {
    condition     = !contains(jsondecode(local.policies["backup"]).Statement[1].Condition.StringEquals["kms:ViaService"], "rds.us-east-2.amazonaws.com")
    error_message = "The backup key cannot be used by the database service."
  }
}

run "rejects_purpose_without_services" {
  command = plan

  variables {
    purposes = { data = [] }
  }

  expect_failures = [var.purposes]
}
