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
    condition     = toset(keys(output.arns)) == toset(["data", "backup", "messages"]) && local.replica_regions == toset(["us-west-2"])
    error_message = "A data key, a backup key and a messages key, each replicated to Oregon."
  }

  assert {
    condition     = local.service_principals.messages == ["sns", "events", "cloudwatch", "s3"] && local.service_principals.data == ["rds"] && !contains(keys(local.service_principals), "backup")
    error_message = "SNS, EventBridge and alarms use the messages key as themselves; only RDS does so with the data key (an Active Directory secret), and none with the backup key."
  }
}
