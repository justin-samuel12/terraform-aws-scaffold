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
    condition     = length(local.problems) == 0 && toset(keys(module.sqs_queue.arns)) == toset(["production-orders", "production-orders-dlq", "production-payments.fifo", "production-receipts"]) && toset(keys(module.sns_topic)) == toset(["orders", "payments"])
    error_message = "A queue for each file in queue/, a topic for each in topic/, named <environment>-<file>, with .fifo for FIFO; an empty file is a queue with the provider's defaults."
  }

  assert {
    condition     = local.queue_arns.payments == "arn:aws:sqs:us-east-2:444444444444:production-payments.fifo" && local.topic_arns.orders == "arn:aws:sns:us-east-2:444444444444:production-orders"
    error_message = "Each queue's and topic's ARN is known from its name."
  }

  assert {
    condition     = local.sqs_queues["production-orders"].visibility_timeout_seconds == 180 && local.sqs_queues["production-orders"].receive_wait_time_seconds == 20 && local.sqs_queues["production-receipts"].receive_wait_time_seconds == null
    error_message = "A queue has the arguments its file writes and no others."
  }

  assert {
    condition     = local.sqs_queues["production-orders"].redrive_policy == { dead_letter_target_arn = "arn:aws:sqs:us-east-2:444444444444:production-orders-dlq", max_receive_count = 3 } && length([for q in local.sqs_queues : q if q.redrive_policy != null]) == 1
    error_message = "redrive_policy names its dead-letter queue, which is found by name; no queue gets one it does not write."
  }

  assert {
    condition     = jsonencode(local.sqs_queues["production-orders-dlq"].redrive_allow_policy) == jsonencode({ redrive_permission = "byQueue", source_queue_arns = ["arn:aws:sqs:us-east-2:444444444444:production-orders"] })
    error_message = "redrive_allow_policy names the queues it takes failures from."
  }

  assert {
    condition     = jsonencode(local.statements.queue.orders[0].condition[0].values) == jsonencode([local.topic_arns.orders]) && jsonencode(local.statements.queue.orders[0].resources) == jsonencode([local.queue_arns.orders])
    error_message = "A queue's own name in resources, and a topic's in aws:SourceArn, become their ARNs."
  }

  assert {
    condition     = jsonencode(local.statements.queue.orders[1].principals[0].identifiers) == jsonencode(["arn:aws:iam::111111111111:root", "222222222222"]) && local.statements.queue.orders[1].effect == "Allow"
    error_message = "An environment's name is its account, from config/; an account ID is used as written."
  }

  assert {
    condition     = jsonencode(local.statements.topic.orders[0].condition[0].values) == jsonencode(["444444444444"])
    error_message = "An environment's name in aws:SourceAccount is its account ID."
  }

  assert {
    condition     = local.subscriptions.orders.orders.endpoint == local.queue_arns.orders && local.subscriptions.orders["orders-team@example.com"].endpoint == "orders-team@example.com"
    error_message = "An sqs endpoint names a queue in this stack; anything else is used as written."
  }

  assert {
    condition     = jsondecode(local.subscriptions.orders["orders-team@example.com"].filter_policy) == { status = ["failed"] } && local.subscriptions.orders.orders.raw_message_delivery && local.subscriptions.orders["orders-team@example.com"].raw_message_delivery == null
    error_message = "A filter policy is written as YAML and passed on as JSON."
  }
}

run "nothing" {
  command = plan

  variables {
    config_dir = "tests/empty"
  }

  assert {
    condition     = length(module.sqs_queue.arns) == 0 && length(module.sns_topic) == 0
    error_message = "With no files, nothing is built."
  }
}

run "refused" {
  command = plan

  variables {
    config_dir = "tests/bad"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "orders.yml: a file belongs in queue/ (an aws_sqs_queue) or topic/ (an aws_sns_topic)"),
      contains(local.problems, "queue/typo.yml: keys are fifo_queue, content_based_deduplication, visibility_timeout_seconds, message_retention_seconds, delay_seconds, receive_wait_time_seconds, redrive_policy, redrive_allow_policy, policy, as aws_sqs_queue takes them"),
      contains(local.problems, "topic/missing.yml: keys are fifo_topic, content_based_deduplication, policy, sns_topic_subscription, as aws_sns_topic takes them"),
      contains(local.problems, "queue/plain.yml: a statement takes effect, actions, resources, principals, condition, as aws_iam_policy_document does"),
      contains(local.problems, "queue/plain.yml: resource elsewhere is not a queue in this stack (a file named queue/elsewhere.yml) or an ARN"),
      contains(local.problems, "queue/plain.yml: the AWS principal staging is not an environment in config/, a 12-digit account ID or an ARN"),
      contains(local.problems, "queue/plain.yml: redrive_policy.dead_letter_target_arn nowhere is not a queue in this stack (a file named queue/nowhere.yml) or an ARN"),
      contains(local.problems, "topic/missing.yml: endpoint nowhere is not a queue in this stack (a file named queue/nowhere.yml) or a queue's ARN"),
      contains(local.problems, "topic/missing.yml: a Lambda function subscribes itself, from its own file in the lambda stack (sns_topic_subscription.topic_arn: missing), so the two stacks never wait for each other"),
      contains(local.problems, "topic/fifo.yml: a FIFO topic delivers only to FIFO queues, and plain is not one"),
      contains(local.problems, "topic/fifo.yml: queue/plain.yml has no policy statement letting sns.amazonaws.com send to it, so nothing the topic delivers would arrive"),
    ])
    error_message = "Each mistake is named: a file outside queue/ and topic/, keys that are not arguments, names that are not in the stack, an unknown environment, a Lambda subscription, a FIFO mismatch and a queue the topic cannot deliver to."
  }

  expect_failures = [output.queues]
}

run "refuses_a_name_in_two_folders" {
  command = plan

  variables {
    config_dir = "tests/two-folders"
  }

  assert {
    condition     = contains(local.problems, "queue/orders.yml is in more than one folder (queue/a/orders.yml, queue/b/orders.yml); a queue's name is its file's, so it must be unique")
    error_message = "Two files with one name are refused."
  }

  expect_failures = [output.queues]
}
