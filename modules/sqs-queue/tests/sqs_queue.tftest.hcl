mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults        = { arn = "arn:aws:sqs:us-east-2:111111111111:queue" }
  }
}

variables {
  kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-messages"
  queues = {
    production-orders = {
      visibility_timeout_seconds = 180
      redrive_policy             = { dead_letter_target_arn = "arn:aws:sqs:us-east-2:111111111111:production-orders-dlq", max_receive_count = 3 }
      policy_statements = [{
        actions    = ["sqs:SendMessage"]
        resources  = ["arn:aws:sqs:us-east-2:111111111111:production-orders"]
        principals = [{ type = "Service", identifiers = ["sns.amazonaws.com"] }]
        condition  = [{ test = "ArnEquals", variable = "aws:SourceArn", values = ["arn:aws:sns:us-east-2:111111111111:production-orders"] }]
      }]
    }
    production-orders-dlq = {
      message_retention_seconds = 1209600
      redrive_allow_policy      = { redrive_permission = "byQueue", source_queue_arns = ["arn:aws:sqs:us-east-2:111111111111:production-orders"] }
    }
  }
}

run "queue_and_dead_letter_queue" {
  command = plan

  assert {
    condition     = toset(keys(aws_sqs_queue.queues)) == toset(["production-orders", "production-orders-dlq"]) && aws_sqs_queue.queues["production-orders"].visibility_timeout_seconds == 180
    error_message = "One queue per entry, with the arguments it was given."
  }

  assert {
    condition     = alltrue([for q in aws_sqs_queue.queues : q.kms_master_key_id == var.kms_key_arn])
    error_message = "Every queue is encrypted with the messages key."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.queues["production-orders"].redrive_policy) == { deadLetterTargetArn = "arn:aws:sqs:us-east-2:111111111111:production-orders-dlq", maxReceiveCount = 3 } && toset(keys(aws_sqs_queue_redrive_policy.queues)) == toset(["production-orders"])
    error_message = "Only a queue with a redrive_policy sends its failures on."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.queues["production-orders-dlq"].redrive_allow_policy) == { redrivePermission = "byQueue", sourceQueueArns = ["arn:aws:sqs:us-east-2:111111111111:production-orders"] }
    error_message = "The dead-letter queue accepts only the queues it names."
  }

  assert {
    condition     = local.policies["production-orders-dlq"][0].Sid == "DenyInsecureTransport" && length(local.policies["production-orders-dlq"]) == 1
    error_message = "Every queue's policy refuses anything not over TLS, and holds nothing else unless written."
  }

  assert {
    condition     = jsonencode(local.policies["production-orders"][1]) == jsonencode({ Action = ["sqs:SendMessage"], Condition = { ArnEquals = { "aws:SourceArn" = ["arn:aws:sns:us-east-2:111111111111:production-orders"] } }, Effect = "Allow", Principal = { Service = ["sns.amazonaws.com"] }, Resource = ["arn:aws:sqs:us-east-2:111111111111:production-orders"] })
    error_message = "A written statement becomes the policy's JSON, as aws_iam_policy_document writes it."
  }
}

run "fifo" {
  command = plan

  variables {
    queues = { "production-payments.fifo" = { fifo_queue = true, content_based_deduplication = true } }
  }

  assert {
    condition     = aws_sqs_queue.queues["production-payments.fifo"].fifo_queue && aws_sqs_queue.queues["production-payments.fifo"].content_based_deduplication
    error_message = "A FIFO queue is named with .fifo."
  }
}

run "rejects_fifo_without_its_suffix" {
  command = plan

  variables {
    queues = { production-payments = { fifo_queue = true } }
  }

  expect_failures = [var.queues]
}

run "rejects_long_polling_past_twenty_seconds" {
  command = plan

  variables {
    queues = { production-orders = { receive_wait_time_seconds = 30 } }
  }

  expect_failures = [var.queues]
}
