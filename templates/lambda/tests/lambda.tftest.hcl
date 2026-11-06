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
    condition     = toset(keys(output.arns)) == toset(["hello"]) && length(local.problems) == 0
    error_message = "One function per file, built from src/<name>/."
  }

  assert {
    condition     = jsonencode(local.statements.hello) == jsonencode([{ effect = "Allow", actions = ["s3:GetObject"], resources = ["arn:aws:s3:::example-reports/*"], condition = [{ test = "StringEquals", variable = "s3:ExistingObjectTag/Public", values = ["false"] }] }])
    error_message = "A statement keeps its effect and condition."
  }
}

run "nothing_listed" {
  command = plan

  variables {
    config_dir = "tests/empty"
  }

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
    condition     = toset(keys(module.lambda_function)) == toset(["orders", "audit"]) && length(local.problems) == 0
    error_message = "Functions reading a queue and subscribing to a topic, both found by name."
  }

  assert {
    condition     = local.topic_names == toset(["operations-orders"]) && jsondecode(local.subscriptions.audit.orders.filter_policy) == { status = ["failed"] }
    error_message = "A topic's name is this environment's topic, found by name; the function subscribes itself, with its filter."
  }

  assert {
    condition     = local.queue_names == { orders = "operations-orders" }
    error_message = "A queue's name is this environment's queue, found by name."
  }
}

run "refuses_keys_that_are_not_arguments" {
  command = plan

  variables {
    config_dir = "tests/not-native"
  }

  assert {
    condition = alltrue([
      contains(local.problems, "legacy.yml: keys are runtime, handler, memory_size, timeout, environment, statement, cloudwatch_event_rule, cloudwatch_log_group, event_source_mapping, sns_topic_subscription"),
      contains(local.problems, "legacy.yml: statement is a list; each takes effect, actions, resources, condition, as aws_iam_policy_document does, and needs actions and resources"),
      contains(local.problems, "legacy.yml: event_source_mapping takes event_source_arn, batch_size, maximum_batching_window_in_seconds, function_response_types, with event_source_arn a queue's name in this environment or its ARN"),
    ])
    error_message = "A key that is not an argument, in the file, a statement or event_source_mapping, is named."
  }

  expect_failures = [output.arns]
}

run "refuses_a_name_in_two_folders" {
  command = plan

  variables {
    config_dir = "tests/two-folders"
  }

  assert {
    condition     = contains(local.problems, "hello.yml is in more than one folder (a/hello.yml, b/hello.yml); a function's name is its file's, so it must be unique")
    error_message = "Two files with one name are refused."
  }

  expect_failures = [output.arns]
}
