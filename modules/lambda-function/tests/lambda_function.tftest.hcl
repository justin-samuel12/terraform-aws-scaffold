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
