# Function files turned into functions; AWS is mocked, the code is zipped for real -- docs/global.md.
mock_provider "aws" {}

variables {
  environment = "operations"
}

run "hello" {
  command = plan

  variables {
    config_dir = "tests/functions"
  }

  assert {
    condition     = toset(keys(output.arns)) == toset(["hello"])
    error_message = "One function per file, built from src/<name>/."
  }
}

run "nothing_listed" {
  command = plan

  assert {
    condition     = output.arns == {}
    error_message = "Without files, no functions."
  }
}

run "queue_consumers" {
  command = plan

  variables {
    config_dir = "tests/consumers"
  }

  override_data {
    target = data.aws_sqs_queue.queues["orders"]
    values = { arn = "arn:aws:sqs:us-east-2:111111111111:operations-orders" }
  }

  override_data {
    target = data.aws_sns_topic.topics["operations-orders"]
    values = { arn = "arn:aws:sns:us-east-2:111111111111:operations-orders" }
  }

  assert {
    condition     = local.topic_names == toset(["operations-orders"]) && jsondecode(local.subscriptions.audit.orders.filter_policy) == { status = ["failed"] }
    error_message = "topic:orders is this environment's topic, found by name; the function subscribes itself, with its filter."
  }

  assert {
    condition     = local.queue_names == { orders = "operations-orders" } && toset(keys(module.lambda_function)) == toset(["orders", "legacy", "audit"])
    error_message = "queue:orders is this environment's queue, found by name; a queue's ARN is used as it is."
  }

  assert {
    condition     = contains(local.problems, "legacy.yml: event_source_mapping takes event_source_arn (queue:<name>, or a queue's ARN), batch_size and maximum_batching_window_in_seconds")
    error_message = "A misspelt event_source_mapping key is named."
  }

  expect_failures = [output.arns]
}
