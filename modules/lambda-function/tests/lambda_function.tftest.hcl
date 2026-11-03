# What the module builds and refuses; AWS is mocked, the code is zipped for real -- docs/global.md.
mock_provider "aws" {}

variables {
  name        = "hello"
  source_dir  = "tests/src/hello"
  runtime     = "python3.12"
  handler     = "app.handler"
  schedule    = "rate(1 day)"
  environment = { LEVEL = "info" }
}

run "scheduled_function" {
  command = plan

  assert {
    condition     = aws_lambda_function.function.architectures == tolist(["arm64"]) && aws_cloudwatch_log_group.function.retention_in_days == 365
    error_message = "Graviton, with its own log group kept a year."
  }

  assert {
    condition     = length(local.statements) == 1
    error_message = "Without extra statements, the function may only write its own logs."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.schedule[0].schedule_expression == "rate(1 day)" && length(aws_lambda_permission.schedule) == 1
    error_message = "A schedule runs it, and only that schedule may invoke it."
  }
}

run "queue_consumer" {
  command = plan

  variables {
    schedule = null
    queue    = { arn = "arn:aws:sqs:us-east-2:111111111111:production-orders", batch_size = 5 }
  }

  assert {
    condition     = aws_lambda_event_source_mapping.queue[0].batch_size == 5 && aws_lambda_event_source_mapping.queue[0].function_response_types == toset(["ReportBatchItemFailures"]) && length(aws_cloudwatch_event_rule.schedule) == 0
    error_message = "The queue triggers the function in batches, and failed messages are reported one by one."
  }

  assert {
    condition     = local.statements[1].Resource == var.queue.arn && contains(local.statements[1].Action, "sqs:DeleteMessage") && local.statements[2].Condition.StringLike["kms:ViaService"] == "sqs.*.amazonaws.com"
    error_message = "The function may read and delete only its own queue's messages, and decrypt them only through SQS."
  }
}

run "topic_subscriber" {
  command = plan

  variables {
    schedule = null
    topics = {
      orders = { arn = "arn:aws:sns:us-east-2:111111111111:production-orders", filter_policy = "{\"status\":[\"failed\"]}" }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.topics["orders"].protocol == "lambda" && aws_sns_topic_subscription.topics["orders"].topic_arn == "arn:aws:sns:us-east-2:111111111111:production-orders"
    error_message = "The function subscribes itself to the topic."
  }

  assert {
    condition     = aws_lambda_permission.topics["orders"].principal == "sns.amazonaws.com" && aws_lambda_permission.topics["orders"].source_arn == "arn:aws:sns:us-east-2:111111111111:production-orders" && aws_lambda_permission.topics["orders"].statement_id == "sns-orders"
    error_message = "Only that topic may invoke it."
  }
}

run "rejects_a_secret_in_the_environment" {
  command = plan

  variables {
    environment = { DB_PASSWORD = "hunter2" }
  }

  expect_failures = [var.environment]
}

run "rejects_everything_on_everything" {
  command = plan

  variables {
    statements = [{ actions = ["*"], resources = ["*"] }]
  }

  expect_failures = [var.statements]
}
