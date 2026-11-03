# Message files turned into queues and topics, against a mocked AWS -- docs/messaging.md.
# Production uses the global account (444...); operations has its own (111...).
mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "444444444444" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = data.aws_kms_key.messages[0]
  values = { arn = "arn:aws:kms:us-east-2:444444444444:key/mrk-messages" }
}

override_data {
  target = module.sns_topic.data.aws_caller_identity.current
  values = { account_id = "444444444444" }
}

override_data {
  target = module.sns_topic.data.aws_partition.current
  values = { partition = "aws" }
}

override_data {
  target = module.sqs_queue.data.aws_partition.current
  values = { partition = "aws" }
}

variables {
  environment = "production"
  region      = "us-east-2"
  config_path = "../../tests/stacks"
}

run "orders" {
  command = plan

  variables {
    config_dir = "tests/orders"
  }

  assert {
    condition     = toset(keys(module.sqs_queue)) == toset(["orders", "payments", "receipts"]) && toset(keys(module.sns_topic)) == toset(["orders", "payments"])
    error_message = "A queue for each file with queue:, a topic for each file with topic:, even when the block is empty."
  }

  assert {
    condition     = local.queue_arns.payments == "arn:aws:sqs:us-east-2:444444444444:production-payments.fifo" && local.topic_arns.orders == "arn:aws:sns:us-east-2:444444444444:production-orders"
    error_message = "Named <environment>-<file>, with .fifo for FIFO."
  }

  assert {
    condition     = local.subscriptions.orders["queue:orders"].endpoint == local.queue_arns.orders && local.subscriptions.orders["lambda:audit"].endpoint == "arn:aws:lambda:us-east-2:444444444444:function:production-audit"
    error_message = "queue: and lambda: name this environment's own queue and function."
  }

  assert {
    condition     = jsondecode(local.subscriptions.orders["orders-team@example.com"].filter_policy) == { status = ["failed"] } && local.subscriptions.orders["queue:orders"].raw_message_delivery
    error_message = "A filter policy is written as YAML and passed on as JSON."
  }

  assert {
    condition     = local.delivering_topics.orders == toset([local.topic_arns.orders]) && length(local.delivering_topics.receipts) == 0
    error_message = "A queue lets in exactly the topics that deliver into it."
  }

  assert {
    condition     = local.other_accounts.orders.senders == toset(["111111111111"]) && local.other_accounts.orders.consumers == toset(["222222222222"]) && local.other_accounts.orders.publishers == toset(["111111111111"])
    error_message = "Operations is found through config/, an ID is used as it is, and production's own account needs no policy."
  }

  assert {
    condition     = local.publisher_services.orders == toset(["cloudwatch"])
    error_message = "Alarms may publish to the topic."
  }

  assert {
    condition     = length(local.problems) == 0
    error_message = "The files are usable."
  }
}

run "refused" {
  command = plan

  variables {
    config_dir = "tests/bad"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "typo.yml: queue keys are fifo_queue, content_based_deduplication, visibility_timeout_seconds, message_retention_seconds, delay_seconds, receive_wait_time_seconds, dead_letter, senders, consumers"),
      contains(local.problems, "missing.yml: queue:nowhere names no queue in this stack"),
      contains(local.problems, "fifo.yml: a FIFO topic delivers only to FIFO queues, and queue:fifo is not one"),
      contains(local.problems, "fifo.yml: staging is not an environment in config/, a 12-digit account ID, or one of cloudwatch, events, s3"),
      contains(local.problems, "fifo.yml: events cannot send to or read a queue directly; publish to a topic that delivers into it"),
    ])
    error_message = "Unknown keys, a missing queue, a FIFO mismatch, an unknown environment and a service as a sender are each named."
  }

  expect_failures = [output.queues]
}
