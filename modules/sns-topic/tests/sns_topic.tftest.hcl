# What the module builds and refuses, against a mocked AWS -- docs/messaging.md.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:us-east-2:111111111111:production-orders" }
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "111111111111" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  name        = "production-orders"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-messages"
}

run "topic_with_subscribers" {
  command = plan

  variables {
    subscriptions = {
      "queue:orders"    = { protocol = "sqs", endpoint = "arn:aws:sqs:us-east-2:111111111111:production-orders", raw_message_delivery = true }
      "lambda:audit"    = { protocol = "lambda", endpoint = "arn:aws:lambda:us-east-2:111111111111:function:production-audit" }
      "ops@example.com" = { protocol = "email", endpoint = "ops@example.com", filter_policy = jsonencode({ severity = ["high"] }) }
    }
    publisher_services = ["cloudwatch", "events"]
    publisher_accounts = ["222222222222"]
  }

  assert {
    condition     = aws_sns_topic.topic.name == "production-orders" && aws_sns_topic.topic.kms_master_key_id == var.kms_key_arn
    error_message = "One topic, encrypted with the messages key."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.subscriptions) == 3 && aws_sns_topic_subscription.subscriptions["queue:orders"].raw_message_delivery
    error_message = "One subscription per subscriber; a queue can take the raw message."
  }

  assert {
    condition     = toset(keys(aws_lambda_permission.subscriptions)) == toset(["lambda:audit"]) && aws_lambda_permission.subscriptions["lambda:audit"].principal == "sns.amazonaws.com"
    error_message = "A Lambda subscriber lets the topic invoke it; other protocols need no permission."
  }

  assert {
    condition     = local.statements[1].Principal.Service == ["cloudwatch.amazonaws.com", "events.amazonaws.com"] && local.statements[1].Condition.StringEquals["aws:SourceAccount"] == "111111111111" && local.statements[2].Principal.AWS == ["arn:aws:iam::222222222222:root"]
    error_message = "Alarms and EventBridge publish for this account only; another account publishes when named."
  }
}

run "fifo" {
  command = plan

  variables {
    fifo                        = true
    content_based_deduplication = true
  }

  assert {
    condition     = aws_sns_topic.topic.name == "production-orders.fifo" && aws_sns_topic.topic.content_based_deduplication && length(local.statements) == 1
    error_message = "A FIFO topic's name ends in .fifo; with no publishers named, the policy only refuses plain HTTP."
  }
}

run "rejects_plain_http" {
  command = plan

  variables {
    subscriptions = { hook = { protocol = "http", endpoint = "http://example.com/hook" } }
  }

  expect_failures = [var.subscriptions]
}
