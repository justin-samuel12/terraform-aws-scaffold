mock_provider "aws" {}

variables {
  name                = "hello"
  source_dir          = "tests/src/hello"
  runtime             = "python3.12"
  handler             = "app.handler"
  schedule_expression = "rate(1 day)"
  retention_in_days   = 365
  environment         = { LEVEL = "info" }
}

run "scheduled_function" {
  command = plan

  assert {
    condition     = var.architectures == null && aws_cloudwatch_log_group.function.retention_in_days == 365 && aws_lambda_function.function.memory_size == null && aws_lambda_function.function.timeout == null
    error_message = "The architecture is left to the provider, with its own log group kept as long as asked; memory and timeout are the provider's unless given."
  }

  assert {
    condition     = length(local.statements) == 1
    error_message = "Without extra statements, the function may only write its own logs."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.rule[0].schedule_expression == "rate(1 day)" && length(aws_lambda_permission.rule) == 1
    error_message = "A schedule runs it, and only that schedule may invoke it."
  }
}

run "queue_consumer" {
  command = plan

  variables {
    schedule_expression  = null
    event_source_mapping = { event_source_arn = "arn:aws:sqs:us-east-2:111111111111:production-orders", batch_size = 5, function_response_types = ["ReportBatchItemFailures"] }
  }

  assert {
    condition     = aws_lambda_event_source_mapping.queue[0].batch_size == 5 && aws_lambda_event_source_mapping.queue[0].function_response_types == toset(["ReportBatchItemFailures"]) && length(aws_cloudwatch_event_rule.rule) == 0
    error_message = "The queue triggers the function in batches, and failed messages are reported one by one."
  }

  assert {
    condition     = local.statements[1].Resource == var.event_source_mapping.event_source_arn && contains(local.statements[1].Action, "sqs:DeleteMessage") && local.statements[2].Condition.StringLike["kms:ViaService"] == "sqs.*.amazonaws.com"
    error_message = "The function may read and delete only its own queue's messages, and decrypt them only through SQS."
  }
}

run "topic_subscriber" {
  command = plan

  variables {
    schedule_expression = null
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

run "statement_keeps_effect_and_condition" {
  command = plan

  variables {
    statements = [{ effect = "Deny", actions = ["s3:DeleteObject"], resources = ["arn:aws:s3:::reports/*"], condition = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }] }]
  }

  assert {
    condition     = jsonencode(local.statements[1]) == jsonencode({ Action = ["s3:DeleteObject"], Condition = { Bool = { "aws:SecureTransport" = ["false"] } }, Effect = "Deny", Resource = ["arn:aws:s3:::reports/*"] })
    error_message = "A statement keeps its effect and condition."
  }
}

run "rejects_a_retention_logs_do_not_have" {
  command = plan

  variables {
    retention_in_days = 42
  }

  expect_failures = [var.retention_in_days]
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

run "event_driven_in_a_vpc" {
  command = plan

  variables {
    schedule_expression = null
    event_pattern       = "{\"source\":[\"aws.acm\"]}"
    architectures       = ["arm64"]
    layers              = ["arn:aws:lambda:us-east-2:111111111111:layer:cryptography:1"]
    vpc_config          = { subnet_ids = ["subnet-1", "subnet-2"], security_group_ids = ["sg-1"] }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.rule[0].event_pattern == var.event_pattern && aws_cloudwatch_event_rule.rule[0].schedule_expression == null && length(aws_lambda_permission.rule) == 1
    error_message = "An event pattern runs it, and only that rule may invoke it."
  }

  assert {
    condition     = aws_lambda_function.function.vpc_config[0].security_group_ids == toset(["sg-1"]) && length(aws_iam_role_policy_attachment.vpc) == 1 && length(aws_lambda_function.function.layers) == 1 && aws_lambda_function.function.architectures == tolist(["arm64"])
    error_message = "A function in a VPC keeps its subnets, groups and layers, and may manage its network interfaces."
  }
}
