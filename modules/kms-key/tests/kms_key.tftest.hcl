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
  environment     = "operations"
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
    condition     = aws_kms_alias.keys["data"].name == "alias/operations-data" && length(aws_kms_replica_key.replicas) == 2
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

run "messages_for_services_and_other_accounts" {
  command = plan

  variables {
    purposes           = { data = ["rds"], messages = ["sqs", "sns"] }
    service_principals = { messages = ["sns", "cloudwatch"] }
    caller_accounts    = { messages = ["222222222222", "111111111111"] }
  }

  assert {
    condition     = jsondecode(local.policies["messages"]).Statement[2].Principal.Service == ["cloudwatch.amazonaws.com", "sns.amazonaws.com"] && jsondecode(local.policies["messages"]).Statement[2].Condition.StringEquals["aws:SourceAccount"] == "111111111111"
    error_message = "SNS and alarms use the messages key as themselves, for this account only."
  }

  assert {
    condition     = jsondecode(local.policies["messages"]).Statement[1].Condition.StringEquals["kms:CallerAccount"] == ["111111111111", "222222222222"]
    error_message = "Another account may use the key through SQS and SNS; this account is listed once, first."
  }

  assert {
    condition     = length(jsondecode(local.policies["data"]).Statement) == 2 && jsondecode(local.policies["data"]).Statement[1].Condition.StringEquals["kms:CallerAccount"] == ["111111111111"]
    error_message = "The data key gets neither: only this account, only through its services."
  }
}

run "rejects_purpose_without_services" {
  command = plan

  variables {
    purposes = { data = [] }
  }

  expect_failures = [var.purposes]
}
