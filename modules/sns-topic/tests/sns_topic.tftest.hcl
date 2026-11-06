mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:us-east-2:111111111111:production-orders" }
  }
}

variables {
  name        = "production-orders"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-messages"
}

run "topic_with_subscribers" {
  command = plan

  variables {
    subscriptions = {
      orders            = { protocol = "sqs", endpoint = "arn:aws:sqs:us-east-2:111111111111:production-orders", raw_message_delivery = true }
      "ops@example.com" = { protocol = "email", endpoint = "ops@example.com", filter_policy = jsonencode({ severity = ["high"] }) }
    }
    policy_statements = [{
      actions    = ["sns:Publish"]
      resources  = ["arn:aws:sns:us-east-2:111111111111:production-orders"]
      principals = [{ type = "Service", identifiers = ["cloudwatch.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = ["111111111111"] }]
    }]
  }

  assert {
    condition     = aws_sns_topic.topic.name == "production-orders" && aws_sns_topic.topic.kms_master_key_id == var.kms_key_arn
    error_message = "One topic, encrypted with the messages key."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.subscriptions) == 2 && aws_sns_topic_subscription.subscriptions["orders"].raw_message_delivery
    error_message = "One subscription per entry; a queue can take the raw message."
  }

  assert {
    condition     = local.statements[0].Sid == "DenyInsecureTransport" && jsonencode(local.statements[1]) == jsonencode({ Action = ["sns:Publish"], Condition = { StringEquals = { "aws:SourceAccount" = ["111111111111"] } }, Effect = "Allow", Principal = { Service = ["cloudwatch.amazonaws.com"] }, Resource = ["arn:aws:sns:us-east-2:111111111111:production-orders"] })
    error_message = "The policy refuses plain HTTP, then holds the statements written."
  }
}

run "fifo" {
  command = plan

  variables {
    name                        = "production-orders.fifo"
    fifo_topic                  = true
    content_based_deduplication = true
  }

  assert {
    condition     = aws_sns_topic.topic.name == "production-orders.fifo" && aws_sns_topic.topic.content_based_deduplication && length(local.statements) == 1
    error_message = "A FIFO topic's name ends in .fifo; with nothing written, the policy only refuses plain HTTP."
  }
}

run "rejects_plain_http" {
  command = plan

  variables {
    subscriptions = { hook = { protocol = "http", endpoint = "http://example.com/hook" } }
  }

  expect_failures = [var.subscriptions]
}

run "rejects_a_lambda_subscription" {
  command = plan

  variables {
    subscriptions = { audit = { protocol = "lambda", endpoint = "arn:aws:lambda:us-east-2:111111111111:function:production-audit" } }
  }

  expect_failures = [var.subscriptions]
}
