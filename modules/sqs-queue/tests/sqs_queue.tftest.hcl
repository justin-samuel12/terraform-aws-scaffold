# What the module builds and refuses, against a mocked AWS -- docs/messaging.md.
mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults        = { arn = "arn:aws:sqs:us-east-2:111111111111:queue" }
  }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  name        = "production-orders"
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-messages"
}

run "standard_queue" {
  command = plan

  assert {
    condition     = aws_sqs_queue.queue.name == "production-orders" && aws_sqs_queue.dead_letter.name == "production-orders-dlq" && aws_sqs_queue.dead_letter.message_retention_seconds == 1209600
    error_message = "A queue and its dead-letter queue, which keeps failures the full 14 days."
  }

  assert {
    condition     = aws_sqs_queue.queue.kms_master_key_id == var.kms_key_arn && aws_sqs_queue.dead_letter.kms_master_key_id == var.kms_key_arn && aws_sqs_queue.queue.receive_wait_time_seconds == 20
    error_message = "Both encrypted with the messages key; long polling by default."
  }

  assert {
    condition     = length(local.queue_statements) == 1 && local.queue_statements[0].Sid == "DenyInsecureTransport"
    error_message = "Without topics or other accounts, the policy only refuses anything not over TLS."
  }
}

run "fifo_with_topics_and_accounts" {
  command = plan

  variables {
    fifo                        = true
    content_based_deduplication = true
    topic_arns                  = ["arn:aws:sns:us-east-2:111111111111:production-orders.fifo"]
    sender_accounts             = ["222222222222"]
    consumer_accounts           = ["333333333333"]
  }

  assert {
    condition     = aws_sqs_queue.queue.name == "production-orders.fifo" && aws_sqs_queue.dead_letter.name == "production-orders-dlq.fifo" && aws_sqs_queue.dead_letter.fifo_queue
    error_message = "A FIFO queue's name ends in .fifo, and its dead-letter queue is FIFO too."
  }

  assert {
    condition     = local.queue_statements[1].Condition.ArnEquals["aws:SourceArn"] == tolist(["arn:aws:sns:us-east-2:111111111111:production-orders.fifo"]) && local.queue_statements[1].Principal.Service == "sns.amazonaws.com"
    error_message = "SNS may deliver, but only from the named topics."
  }

  assert {
    condition     = local.queue_statements[2].Principal.AWS == ["arn:aws:iam::222222222222:root"] && contains(local.queue_statements[3].Action, "sqs:DeleteMessage") && !contains(local.queue_statements[2].Action, "sqs:ReceiveMessage")
    error_message = "Senders only send; consumers receive and delete."
  }
}

run "rejects_bad_account" {
  command = plan

  variables {
    sender_accounts = ["prod"]
  }

  expect_failures = [var.sender_accounts]
}
