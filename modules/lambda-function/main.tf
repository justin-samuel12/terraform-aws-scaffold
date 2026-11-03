# The zip's file modes are fixed, so a different umask on another machine is not a code change.
data "archive_file" "code" {
  type             = "zip"
  source_dir       = var.source_dir
  output_path      = "${path.root}/.terraform/lambda/${var.name}.zip"
  output_file_mode = "0644"
}

resource "aws_iam_role" "function" {
  name = "lambda-${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Name = "lambda-${var.name}" }
}

# Only its own log group, plus whatever the function's file asks for.
resource "aws_iam_role_policy" "function" {
  name   = "lambda-${var.name}"
  role   = aws_iam_role.function.id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days

  tags = { Name = var.name }
}

resource "aws_lambda_function" "function" {
  function_name    = var.name
  role             = aws_iam_role.function.arn
  runtime          = var.runtime
  handler          = var.handler
  architectures    = ["arm64"]
  memory_size      = var.memory
  timeout          = var.timeout
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256

  dynamic "environment" {
    for_each = length(var.environment) > 0 ? [var.environment] : []
    content {
      variables = environment.value
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.function.name
  }

  tags = { Name = var.name }

  depends_on = [aws_iam_role_policy.function]
}

resource "aws_cloudwatch_event_rule" "schedule" {
  count = var.schedule == null ? 0 : 1

  name                = "lambda-${var.name}"
  schedule_expression = var.schedule

  tags = { Name = "lambda-${var.name}" }
}

resource "aws_cloudwatch_event_target" "schedule" {
  count = var.schedule == null ? 0 : 1

  rule = aws_cloudwatch_event_rule.schedule[0].name
  arn  = aws_lambda_function.function.arn

  # The schedule may start firing at once; the function must already allow it.
  depends_on = [aws_lambda_permission.schedule]
}

resource "aws_lambda_permission" "schedule" {
  count = var.schedule == null ? 0 : 1

  statement_id  = "schedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[0].arn
}

# Messages that fail are reported one by one, so a batch is not retried whole for one bad message.
resource "aws_lambda_event_source_mapping" "queue" {
  count = var.queue == null ? 0 : 1

  event_source_arn                   = var.queue.arn
  function_name                      = aws_lambda_function.function.arn
  batch_size                         = var.queue.batch_size
  maximum_batching_window_in_seconds = var.queue.maximum_batching_window_in_seconds
  function_response_types            = ["ReportBatchItemFailures"]

  tags = { Name = "lambda-${var.name}" }

  depends_on = [aws_iam_role_policy.function]
}
